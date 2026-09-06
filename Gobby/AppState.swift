import AppKit
import Carbon
import Combine
import Foundation
import SwiftUI

extension Notification.Name {
    static let gobbyHotkeysDidChange = Notification.Name("gobbyHotkeysDidChange")
    static let gobbyRowsShouldCloseSwipeActions = Notification.Name("gobbyRowsShouldCloseSwipeActions")
}

@MainActor
final class AppState: ObservableObject {
    let store: ClipboardStore
    @Published var toast: String?
    @Published var renameItem: ClipboardItem?
    @Published var renameDraft = ""
    @Published private(set) var hotkeyIssue: String?
    private var settingsWindow: NSWindow?
    private var gobbyPanel: NSPanel?
    private var storeChanges: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private var globalHotkeys: GlobalHotkeyManager?

    private lazy var monitor = ClipboardMonitor { [weak self] capture in
        guard let self else { return }
        let limit = UserDefaults.standard.object(forKey: "historyLimit") as? Int ?? 250
        self.store.append(
            kind: capture.kind,
            content: capture.content,
            imageData: capture.imageData,
            sourceAppName: capture.sourceAppName,
            sourceAppBundleIdentifier: capture.sourceAppBundleIdentifier,
            imageFormat: capture.imageFormat,
            limit: limit
        )
    }

    init() {
        UserDefaults.standard.register(defaults: [
            "historyLimit": 250,
            "historyRetentionDays": 30,
            "imageHistoryEnabled": true,
            "ocrEnabled": true,
            "liquidGlass": true,
            "gobbyOpenShortcut": "optionSpace",
            "gobbyPasteNextShortcut": "optionV"
        ])
        store = ClipboardStore()
        storeChanges = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        globalHotkeys = GlobalHotkeyManager { [weak self] action in
            DispatchQueue.main.async {
                switch action {
                case .openGobby:
                    self?.showGobbyPanel()
                case .pasteNext:
                    self?.pasteNextStackItem()
                }
            }
        }
        configureGlobalHotkeys()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: .gobbyHotkeysDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.configureGlobalHotkeys()
            }
        }
        monitor.start()
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    func copy(_ item: ClipboardItem) {
        store.writeToSystemClipboard(item)
        monitor.ignoreNextChange()
        showToast("Panoya kopyalandı — iPhone’da yapıştırabilirsiniz.")
    }

    func copyAsPlainText(_ item: ClipboardItem) {
        store.writePlainTextToSystemClipboard(item)
        monitor.ignoreNextChange()
        showToast("Düz metin panoya kopyalandı.")
    }

    func pasteNextStackItem() {
        guard let item = store.advanceStack() else {
            showToast("Gobby Stack boş.")
            return
        }
        store.writeToSystemClipboard(item)
        monitor.ignoreNextChange()
        showToast("Stack öğesi panoya kopyalandı: \(item.title)")
    }

    func requestRename(_ item: ClipboardItem) {
        renameItem = item
        renameDraft = item.customName ?? ""
    }

    func commitRename() {
        guard let renameItem else { return }
        store.rename(renameItem, to: renameDraft)
        self.renameItem = nil
        renameDraft = ""
    }

    func showSettings() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let settings = SettingsView().environmentObject(self)
        let controller = NSHostingController(rootView: settings)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gobby Ayarları"
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showGobbyPanel() {
        if let gobbyPanel {
            NSApp.activate(ignoringOtherApps: true)
            gobbyPanel.makeKeyAndOrderFront(nil)
            return
        }

        let controller = NSHostingController(rootView: ContentView().environmentObject(self))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Gobby"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = controller
        panel.center()
        gobbyPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            guard self?.toast == text else { return }
            self?.toast = nil
        }
    }

    private func configureGlobalHotkeys() {
        guard let registration = globalHotkeys?.registerConfiguredHotkeys() else { return }
        var unavailable: [String] = []
        if !registration.open { unavailable.append("Gobby’yi aç") }
        if !registration.pasteNext { unavailable.append("Sıradakini panoya kopyala") }
        hotkeyIssue = unavailable.isEmpty ? nil : "Kullanılamayan genel kısayol: \(unavailable.joined(separator: ", ")). Başka bir uygulama kullanıyor olabilir."
    }
}

private enum GlobalHotkeyAction {
    case openGobby
    case pasteNext
}

private final class GlobalHotkeyManager {
    private let signature: OSType = 0x474F4242 // GOBB
    private let handler: (GlobalHotkeyAction) -> Void
    private var openHotkey: EventHotKeyRef?
    private var pasteNextHotkey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init(handler: @escaping (GlobalHotkeyAction) -> Void) {
        self.handler = handler
        installEventHandler()
        _ = registerConfiguredHotkeys()
    }

    deinit {
        if let openHotkey { UnregisterEventHotKey(openHotkey) }
        if let pasteNextHotkey { UnregisterEventHotKey(pasteNextHotkey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func registerConfiguredHotkeys() -> (open: Bool, pasteNext: Bool) {
        if let openHotkey { UnregisterEventHotKey(openHotkey) }
        if let pasteNextHotkey { UnregisterEventHotKey(pasteNextHotkey) }
        openHotkey = register(id: 1, configuration: UserDefaults.standard.string(forKey: "gobbyOpenShortcut") ?? "optionSpace")
        pasteNextHotkey = register(id: 2, configuration: UserDefaults.standard.string(forKey: "gobbyPasteNextShortcut") ?? "optionV")
        return (openHotkey != nil, pasteNextHotkey != nil)
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                switch hotkeyID.id {
                case 1: manager.handler(.openGobby)
                case 2: manager.handler(.pasteNext)
                default: break
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func register(id: UInt32, configuration: String) -> EventHotKeyRef? {
        let keyCode: UInt32
        let modifiers: UInt32
        switch configuration {
        case "optionShiftSpace":
            keyCode = 49
            modifiers = UInt32(optionKey | shiftKey)
        case "optionV":
            keyCode = 9
            modifiers = UInt32(optionKey)
        case "optionShiftV":
            keyCode = 9
            modifiers = UInt32(optionKey | shiftKey)
        default:
            keyCode = 49
            modifiers = UInt32(optionKey)
        }
        var hotkey: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkey)
        return status == noErr ? hotkey : nil
    }
}
