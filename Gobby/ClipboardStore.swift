import AppKit
import Combine
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

private actor HistoryArchiveWriter {
    private var latestGeneration = 0

    func write(_ items: [ClipboardItem], generation: Int, to url: URL) {
        guard generation >= latestGeneration else { return }
        latestGeneration = generation
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var stackEntries: [GobbyStackEntry] = []
    @Published private(set) var stackCursor = 0

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var thumbnailRequests = Set<String>()
    private let archiveWriter = HistoryArchiveWriter()
    private var persistenceGeneration = 0
    private let stackEntriesKey = "gobbyStackEntries"
    private let stackCursorKey = "gobbyStackCursor"

    private var rootURL: URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport.appendingPathComponent("ClipCalendar", isDirectory: true)
    }

    private var imagesURL: URL {
        rootURL.appendingPathComponent("Images", isDirectory: true)
    }

    private var thumbnailsURL: URL {
        imagesURL.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    private var archiveURL: URL {
        rootURL.appendingPathComponent("history.json")
    }

    init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        imageCache.countLimit = 12
        thumbnailCache.countLimit = 200
        createDirectories()
        load()
        loadStack()
        applyRetention(days: UserDefaults.standard.integer(forKey: "historyRetentionDays"))
    }

    func append(
        kind: ClipKind,
        content: String? = nil,
        imageData: Data? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleIdentifier: String? = nil,
        imageFormat: String? = nil,
        limit: Int
    ) {
        let fingerprint = makeFingerprint(kind: kind, content: content, imageData: imageData)
        if let existingIndex = items.firstIndex(where: { $0.fingerprint == fingerprint }) {
            var existing = items.remove(at: existingIndex)
            existing.createdAt = .now
            existing.sourceAppName = sourceAppName ?? existing.sourceAppName
            existing.sourceAppBundleIdentifier = sourceAppBundleIdentifier ?? existing.sourceAppBundleIdentifier
            items.insert(existing, at: 0)
            persist()
            return
        }

        var imageFilename: String?
        var imageWidth: Int?
        var imageHeight: Int?
        if let imageData {
            let normalizedImageFormat = imageFormat?.uppercased() ?? "PNG"
            let fileExtension = normalizedImageFormat == "TIFF" ? "tiff" : "png"
            let filename = "\(UUID().uuidString).\(fileExtension)"
            let url = imagesURL.appendingPathComponent(filename)
            do {
                try imageData.write(to: url, options: .atomic)
                imageFilename = filename
                let metadata = imageMetadata(for: imageData)
                imageWidth = metadata.width
                imageHeight = metadata.height
            } catch {
                return
            }
        }

        let item = ClipboardItem(
            kind: kind,
            content: content,
            imageFilename: imageFilename,
            fingerprint: fingerprint,
            category: classify(kind: kind, content: content),
            sourceAppName: sourceAppName,
            sourceAppBundleIdentifier: sourceAppBundleIdentifier,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            imageFormat: imageFilename == nil ? nil : (imageFormat?.uppercased() ?? "PNG")
        )
        items.insert(item, at: 0)
        if let imageFilename { scheduleThumbnail(for: imageFilename) }
        if let imageData, UserDefaults.standard.object(forKey: "ocrEnabled") as? Bool ?? true {
            recognizeText(in: imageData, itemID: item.id)
        }
        applyRetention(days: UserDefaults.standard.integer(forKey: "historyRetentionDays"))
        trim(to: limit)
        persist()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        persist()
    }

    func rename(_ item: ClipboardItem, to name: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].customName = trimmedName.isEmpty ? nil : trimmedName
        persist()
    }

    func setColor(_ color: ClipColor?, for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].tagColor = color
        items[index].customColorHex = nil
        persist()
    }

    func setCustomColor(hex: String, for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].tagColor = .custom
        items[index].customColorHex = hex
        persist()
    }

    func delete(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        deleteImage(for: removed)
        stackEntries.removeAll { $0.clipboardItemID == removed.id }
        normalizeStackCursor()
        persist()
        persistStack()
    }

    func clearUnpinned() {
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        removed.forEach(deleteImage)
        stackEntries.removeAll { entry in removed.contains { $0.id == entry.clipboardItemID } }
        normalizeStackCursor()
        persist()
        persistStack()
    }

    func clear(categories: Set<ClipCategory>? = nil, includePinned: Bool = true) {
        let removed = items.filter { item in
            let categoryMatches = categories?.contains(item.category) ?? true
            return categoryMatches && (includePinned || !item.isPinned)
        }
        let ids = Set(removed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        removed.forEach(deleteImage)
        stackEntries.removeAll { ids.contains($0.clipboardItemID) }
        normalizeStackCursor()
        persist()
        persistStack()
    }

    func setLimit(_ limit: Int) {
        trim(to: limit)
        persist()
    }

    func applyRetention(days: Int) {
        guard days > 0 else { return }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return }
        let removed = items.filter { !$0.isPinned && $0.createdAt < cutoff }
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        removed.forEach(deleteImage)
        stackEntries.removeAll { ids.contains($0.clipboardItemID) }
        normalizeStackCursor()
        persist()
        persistStack()
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let filename = item.imageFilename else { return nil }
        if let cached = imageCache.object(forKey: filename as NSString) { return cached }
        guard let image = NSImage(contentsOf: imagesURL.appendingPathComponent(filename)) else { return nil }
        imageCache.setObject(image, forKey: filename as NSString)
        return image
    }

    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard let filename = item.imageFilename else { return nil }
        if let cached = thumbnailCache.object(forKey: filename as NSString) { return cached }
        let url = thumbnailURL(for: filename)
        if let thumbnail = NSImage(contentsOf: url) {
            thumbnailCache.setObject(thumbnail, forKey: filename as NSString)
            return thumbnail
        }
        scheduleThumbnail(for: filename)
        return nil
    }

    /// Item is put back on the system clipboard. Apple Universal Clipboard can then paste it on an iPhone.
    func writeToSystemClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            // Use the standard pasteboard-writing path used by a normal Command-C operation.
            pasteboard.writeObjects([NSString(string: item.content ?? "")])
        case .url:
            let value = item.content ?? ""
            if let url = URL(string: value) {
                // Writing NSURL publishes the standard URL representation used by Universal Clipboard.
                pasteboard.writeObjects([url as NSURL])
            }
            pasteboard.setString(value, forType: .URL)
            pasteboard.setString(value, forType: .string)
        case .file:
            if let path = item.content {
                pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
            }
        case .image:
            guard let filename = item.imageFilename,
                  let data = try? Data(contentsOf: imagesURL.appendingPathComponent(filename)) else { return }
            // Publish both an NSImage and PNG data. iOS can negotiate either representation over Handoff.
            if let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
                if let tiff = image.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
            }
            pasteboard.setData(data, forType: item.imageFormat == "TIFF" ? .tiff : .png)
        }
    }

    func writePlainTextToSystemClipboard(_ item: ClipboardItem) {
        let plainText: String
        switch item.kind {
        case .text, .url, .file:
            plainText = item.content ?? ""
        case .image:
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
    }

    var stackItems: [(entry: GobbyStackEntry, item: ClipboardItem)] {
        stackEntries.compactMap { entry in
            guard let item = items.first(where: { $0.id == entry.clipboardItemID }) else { return nil }
            return (entry, item)
        }
    }

    var nextStackItem: ClipboardItem? {
        let entries = stackItems
        guard !entries.isEmpty else { return nil }
        return entries[min(stackCursor, entries.count - 1)].item
    }

    func addToStack(_ item: ClipboardItem) {
        stackEntries.append(GobbyStackEntry(clipboardItemID: item.id))
        normalizeStackCursor()
        persistStack()
    }

    func removeFromStack(_ entry: GobbyStackEntry) {
        stackEntries.removeAll { $0.id == entry.id }
        normalizeStackCursor()
        persistStack()
    }

    func moveStackEntries(from source: IndexSet, to destination: Int) {
        stackEntries.move(fromOffsets: source, toOffset: destination)
        normalizeStackCursor()
        persistStack()
    }

    func clearStack() {
        stackEntries.removeAll()
        stackCursor = 0
        persistStack()
    }

    func restartStack() {
        stackCursor = 0
        persistStack()
    }

    func advanceStack() -> ClipboardItem? {
        let entries = stackItems
        guard !entries.isEmpty else { return nil }
        let index = min(stackCursor, entries.count - 1)
        let item = entries[index].item
        stackCursor = (index + 1) % entries.count
        persistStack()
        return item
    }

    private func createDirectories() {
        try? fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: archiveURL),
              let savedItems = try? decoder.decode([ClipboardItem].self, from: data) else { return }
        items = savedItems.sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        persistenceGeneration += 1
        let snapshot = items
        let generation = persistenceGeneration
        let url = archiveURL
        Task { [archiveWriter] in
            await archiveWriter.write(snapshot, generation: generation, to: url)
        }
    }

    private func loadStack() {
        guard let data = UserDefaults.standard.data(forKey: stackEntriesKey),
              let savedEntries = try? decoder.decode([GobbyStackEntry].self, from: data) else { return }
        let availableIDs = Set(items.map(\.id))
        stackEntries = savedEntries.filter { availableIDs.contains($0.clipboardItemID) }
        stackCursor = UserDefaults.standard.integer(forKey: stackCursorKey)
        normalizeStackCursor()
    }

    private func persistStack() {
        guard let data = try? encoder.encode(stackEntries) else { return }
        UserDefaults.standard.set(data, forKey: stackEntriesKey)
        UserDefaults.standard.set(stackCursor, forKey: stackCursorKey)
    }

    private func normalizeStackCursor() {
        guard !stackEntries.isEmpty else {
            stackCursor = 0
            return
        }
        stackCursor = min(max(stackCursor, 0), stackEntries.count - 1)
    }

    private func trim(to limit: Int) {
        guard limit > 0 else { return }
        let nonPinnedIndices = items.indices.filter { !items[$0].isPinned }
        guard nonPinnedIndices.count > limit else { return }

        let idsToRemove = Set(nonPinnedIndices.dropFirst(limit).map { items[$0].id })
        let removed = items.filter { idsToRemove.contains($0.id) }
        items.removeAll { idsToRemove.contains($0.id) }
        removed.forEach(deleteImage)
        stackEntries.removeAll { idsToRemove.contains($0.clipboardItemID) }
        normalizeStackCursor()
    }

    private func deleteImage(for item: ClipboardItem) {
        guard let filename = item.imageFilename else { return }
        imageCache.removeObject(forKey: filename as NSString)
        thumbnailCache.removeObject(forKey: filename as NSString)
        try? fileManager.removeItem(at: imagesURL.appendingPathComponent(filename))
        try? fileManager.removeItem(at: thumbnailURL(for: filename))
    }

    private func makeFingerprint(kind: ClipKind, content: String?, imageData: Data?) -> String {
        var data = Data(kind.rawValue.utf8)
        data.append(Data((content ?? "").utf8))
        if let imageData { data.append(imageData) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func classify(kind: ClipKind, content: String?) -> ClipCategory {
        switch kind {
        case .url: return .link
        case .image: return .image
        case .file: return .file
        case .text:
            let value = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.range(of: "^#[0-9A-Fa-f]{6,8}$", options: .regularExpression) != nil { return .color }
            if value.range(of: "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$", options: [.regularExpression, .caseInsensitive]) != nil { return .email }
            if value.range(of: "^\\+?[0-9 ()-]{7,}$", options: .regularExpression) != nil { return .phone }
            let codeMarkers = ["func ", "let ", "var ", "import ", "{", "}", "=>", "</"]
            if value.count > 10, codeMarkers.contains(where: value.contains) { return .code }
            return .text
        }
    }

    private func imageMetadata(for data: Data) -> (width: Int?, height: Int?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return (nil, nil) }
        return (properties[kCGImagePropertyPixelWidth] as? Int, properties[kCGImagePropertyPixelHeight] as? Int)
    }

    private func thumbnailURL(for filename: String) -> URL {
        thumbnailsURL.appendingPathComponent("\(filename).png")
    }

    private func scheduleThumbnail(for filename: String) {
        guard !thumbnailRequests.contains(filename) else { return }
        thumbnailRequests.insert(filename)
        let sourceURL = imagesURL.appendingPathComponent(filename)
        let destinationURL = thumbnailURL(for: filename)
        Task.detached(priority: .utility) { [weak self] in
            let didCreate = Self.createThumbnail(from: sourceURL, to: destinationURL)
            await self?.finishThumbnailRequest(filename: filename, didCreate: didCreate)
        }
    }

    private func finishThumbnailRequest(filename: String, didCreate: Bool) {
        thumbnailRequests.remove(filename)
        guard didCreate else { return }
        objectWillChange.send()
    }

    private nonisolated static func createThumbnail(from sourceURL: URL, to destinationURL: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return false }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 420,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private func recognizeText(in data: Data, itemID: UUID) {
        Task.detached(priority: .utility) { [weak self] in
            let text = LocalImageOCR.recognize(data: data)
            guard !text.isEmpty else { return }
            await self?.setOCRText(text, for: itemID)
        }
    }

    private func setOCRText(_ text: String, for itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].ocrText = text
        persist()
    }
}

private enum LocalImageOCR {
    static func recognize(data: Data) -> String {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return "" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["tr-TR", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
                .prefix(4_000)
                .description
        }
    }
}
