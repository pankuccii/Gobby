import AppKit
import Foundation

struct ClipboardCapture {
    let kind: ClipKind
    let content: String?
    let imageData: Data?
    let imageFormat: String?
    let sourceAppName: String?
    let sourceAppBundleIdentifier: String?
}

@MainActor
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var ignoredChangeCount: Int?
    private let handler: (ClipboardCapture) -> Void

    init(handler: @escaping (ClipboardCapture) -> Void) {
        self.handler = handler
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        // NSPasteboard exposes no public change notification. 80 ms keeps capture perceptually instant
        // without the 100 wakeups/second that the previous 10 ms timer caused.
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.inspectPasteboard()
            }
        }
        timer?.tolerance = 0.02
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func ignoreNextChange() {
        ignoredChangeCount = NSPasteboard.general.changeCount
    }

    private func inspectPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if ignoredChangeCount == pasteboard.changeCount {
            ignoredChangeCount = nil
            return
        }

        // Apps may mark clipboard data as transient or concealed. Gobby never tries to capture around
        // those privacy signals and also honours the user's explicit application exclusions.
        let types = Set(pasteboard.types ?? [])
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        guard !types.contains(concealed), !types.contains(transient) else { return }

        let source = NSWorkspace.shared.frontmostApplication
        let sourceBundleIdentifier = source?.bundleIdentifier
        let excludedApps = Set(UserDefaults.standard.stringArray(forKey: "excludedApps") ?? [])
        guard sourceBundleIdentifier.map({ !excludedApps.contains($0) }) ?? true else { return }

        let sourceName = source?.localizedName
        func capture(_ kind: ClipKind, content: String? = nil, imageData: Data? = nil, imageFormat: String? = nil) -> ClipboardCapture {
            ClipboardCapture(
                kind: kind,
                content: content,
                imageData: imageData,
                imageFormat: imageFormat,
                sourceAppName: sourceName,
                sourceAppBundleIdentifier: sourceBundleIdentifier
            )
        }

        let imageHistoryEnabled = UserDefaults.standard.object(forKey: "imageHistoryEnabled") as? Bool ?? true
        if imageHistoryEnabled, let png = pasteboard.data(forType: .png) {
            handler(capture(.image, imageData: png, imageFormat: "PNG"))
            return
        }

        if imageHistoryEnabled, let tiff = pasteboard.data(forType: .tiff) {
            handler(capture(.image, imageData: tiff, imageFormat: "TIFF"))
            return
        }

        if let url = pasteboard.string(forType: .URL), !url.isEmpty {
            handler(capture(.url, content: url))
            return
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let fileURL = URL(string: fileURLString), fileURL.isFileURL {
            handler(capture(.file, content: fileURL.path))
            return
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            handler(capture(.text, content: text))
        }
    }

}
