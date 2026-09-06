import Foundation

enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case text
    case url
    case image
    case file

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "folder"
        }
    }

    var label: String {
        switch self {
        case .text: return "Metin"
        case .url: return "Bağlantı"
        case .image: return "Görüntü"
        case .file: return "Dosya"
        }
    }
}

enum ClipCategory: String, Codable, CaseIterable, Identifiable {
    case text
    case link
    case image
    case file
    case code
    case color
    case email
    case phone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "Metin"
        case .link: return "Bağlantı"
        case .image: return "Görüntü"
        case .file: return "Dosya"
        case .code: return "Kod"
        case .color: return "Renk"
        case .email: return "E-posta"
        case .phone: return "Telefon"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "folder"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .email: return "envelope"
        case .phone: return "phone"
        }
    }
}

enum ClipColor: String, Codable, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case purple
    case pink
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: return "Kırmızı"
        case .orange: return "Turuncu"
        case .yellow: return "Sarı"
        case .green: return "Yeşil"
        case .teal: return "Turkuaz"
        case .blue: return "Mavi"
        case .purple: return "Mor"
        case .pink: return "Pembe"
        case .custom: return "Özel renk"
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: ClipKind
    let content: String?
    let imageFilename: String?
    let fingerprint: String
    var createdAt: Date
    var isPinned: Bool
    var tagColor: ClipColor? = nil
    var customColorHex: String? = nil
    var category: ClipCategory
    var sourceAppName: String?
    var sourceAppBundleIdentifier: String?
    var customName: String?
    var ocrText: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var imageFormat: String?

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        content: String? = nil,
        imageFilename: String? = nil,
        fingerprint: String,
        createdAt: Date = .now,
        isPinned: Bool = false,
        tagColor: ClipColor? = nil,
        customColorHex: String? = nil,
        category: ClipCategory? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleIdentifier: String? = nil,
        customName: String? = nil,
        ocrText: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        imageFormat: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.imageFilename = imageFilename
        self.fingerprint = fingerprint
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.tagColor = tagColor
        self.customColorHex = customColorHex
        self.category = category ?? Self.defaultCategory(for: kind)
        self.sourceAppName = sourceAppName
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.customName = customName
        self.ocrText = ocrText
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageFormat = imageFormat
    }

    var title: String {
        if let customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customName
        }
        switch kind {
        case .image:
            return "Ekran görüntüsü / görüntü"
        case .url:
            return content ?? "Bağlantı"
        case .file:
            return URL(fileURLWithPath: content ?? "").lastPathComponent
        case .text:
            let firstLine = (content ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? "Metin"
            return firstLine.isEmpty ? "Metin" : firstLine
        }
    }

    var preview: String {
        guard kind != .image else { return "Panodan kaydedildi" }
        return content ?? ""
    }

    var searchText: String {
        [title, preview, kind.label, category.label, sourceAppName ?? "", customName ?? "", ocrText ?? ""]
            .joined(separator: " ")
    }

    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.searchNormalized
        guard !normalizedQuery.isEmpty else { return true }
        let normalizedText = searchText.searchNormalized
        if normalizedText.contains(normalizedQuery) { return true }

        let compactQuery = normalizedQuery.replacingOccurrences(of: " ", with: "")
        let compactText = normalizedText.replacingOccurrences(of: " ", with: "")
        guard compactQuery.count <= 12 else { return false }
        return compactQuery.isSubsequence(of: compactText)
    }

    private static func defaultCategory(for kind: ClipKind) -> ClipCategory {
        switch kind {
        case .text: return .text
        case .url: return .link
        case .image: return .image
        case .file: return .file
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, content, imageFilename, fingerprint, createdAt, isPinned
        case tagColor, customColorHex, category, sourceAppName, sourceAppBundleIdentifier
        case customName, ocrText, imageWidth, imageHeight, imageFormat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ClipKind.self, forKey: .kind)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        tagColor = try container.decodeIfPresent(ClipColor.self, forKey: .tagColor)
        customColorHex = try container.decodeIfPresent(String.self, forKey: .customColorHex)
        category = try container.decodeIfPresent(ClipCategory.self, forKey: .category) ?? Self.defaultCategory(for: kind)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        sourceAppBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceAppBundleIdentifier)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        imageWidth = try container.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try container.decodeIfPresent(Int.self, forKey: .imageHeight)
        imageFormat = try container.decodeIfPresent(String.self, forKey: .imageFormat)
    }
}

private extension String {
    var searchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isSubsequence(of text: String) -> Bool {
        var searchIndex = startIndex
        for character in text where searchIndex < endIndex && character == self[searchIndex] {
            formIndex(after: &searchIndex)
        }
        return searchIndex == endIndex
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Otomatik"
        case .light: return "Açık"
        case .dark: return "Koyu"
        }
    }
}

struct GobbyStackEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let clipboardItemID: UUID

    init(id: UUID = UUID(), clipboardItemID: UUID) {
        self.id = id
        self.clipboardItemID = clipboardItemID
    }
}
