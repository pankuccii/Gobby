import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private enum PreferencesSection: String, CaseIterable, Identifiable {
    case general = "Genel"
    case history = "Geçmiş"
    case hotkeys = "Kısayollar"
    case privacy = "Gizlilik"
    case appearance = "Görünüm"
    case advanced = "Gelişmiş"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .history: return "clock.arrow.circlepath"
        case .hotkeys: return "command"
        case .privacy: return "hand.raised"
        case .appearance: return "circle.lefthalf.filled"
        case .advanced: return "wrench.and.screwdriver"
        }
    }

    var description: String {
        switch self {
        case .general: return "Menü çubuğu davranışı ve Continuity"
        case .history: return "Saklama ve temizleme"
        case .hotkeys: return "Klavye ile hızlı erişim"
        case .privacy: return "Yerel veri ve uygulama hariç tutma"
        case .appearance: return "Tema ve panel stili"
        case .advanced: return "Geri alınamaz bakım işlemleri"
        }
    }
}

private enum ClearScope: Identifiable {
    case unpinned
    case text
    case images
    case all

    var id: String { title }

    var title: String {
        switch self {
        case .unpinned: return "Sabitlenmemiş öğeler silinsin mi?"
        case .text: return "Metin geçmişi silinsin mi?"
        case .images: return "Görüntü geçmişi silinsin mi?"
        case .all: return "Tüm geçmiş silinsin mi?"
        }
    }

    var message: String {
        switch self {
        case .unpinned: return "Sabitlenmiş öğeler korunur."
        case .text: return "Metin, bağlantı, kod, renk, e-posta ve telefon öğeleri kaldırılır."
        case .images: return "Kaydedilmiş görüntüler ve OCR metinleri kaldırılır."
        case .all: return "Sabitlenmiş öğeler dahil tüm yerel geçmiş ve Stack referansları kaldırılır."
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.automatic.rawValue
    @AppStorage("liquidGlass") private var liquidGlass = true
    @AppStorage("historyLimit") private var historyLimit = 250
    @AppStorage("historyRetentionDays") private var historyRetentionDays = 30
    @AppStorage("imageHistoryEnabled") private var imageHistoryEnabled = true
    @AppStorage("ocrEnabled") private var ocrEnabled = true
    @State private var section: PreferencesSection = .general
    @State private var confirmClear = false
    @State private var clearScope: ClearScope?
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var appKitAppearance: NSAppearance? {
        switch AppearanceMode(rawValue: appearanceMode) ?? .automatic {
        case .automatic: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    private var usesGlass: Bool {
        liquidGlass && !reduceTransparency
    }

    var body: some View {
        ZStack {
            WindowAppearanceSynchronizer(appearance: appKitAppearance)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            if usesGlass {
                if #available(macOS 26.0, *) {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 0))
                        .ignoresSafeArea()
                } else {
                    VisualEffectView(material: .underWindowBackground, appearance: appKitAppearance)
                        .ignoresSafeArea()
                }
            } else {
                NativeWindowBackground()
                    .ignoresSafeArea()
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: appearanceMode)
            }
            HStack(spacing: 0) {
                sidebar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        pageHeader
                        switch section {
                        case .general: generalPage
                        case .history: historyPage
                        case .hotkeys: hotkeysPage
                        case .privacy: privacyPage
                        case .appearance: appearancePage
                        case .advanced: advancedPage
                        }
                    }
                    .padding(28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 720, height: 540)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: liquidGlass)
        .onAppear {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
        .confirmationDialog(clearScope?.title ?? "Geçmiş silinsin mi?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                performClearScope()
            }
            Button("Vazgeç", role: .cancel) { clearScope = nil }
        } message: {
            Text(clearScope?.message ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "clipboard.fill")
                    .foregroundStyle(.white)
                    .frame(width: 31, height: 31)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Gobby")
                        .font(.headline)
                    Text("Ayarlar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 19)

            ForEach(PreferencesSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .frame(width: 18)
                        Text(item.rawValue)
                        Spacer()
                    }
                    .font(.callout.weight(section == item ? .semibold : .regular))
                    .foregroundStyle(section == item ? Color.accentColor : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(section == item ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Gobby 1.0")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            if usesGlass {
                Rectangle().fill(.bar)
            } else {
                Rectangle().fill(Color.primary.opacity(0.035))
            }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.rawValue)
                .font(.title2.weight(.semibold))
            Text(section.description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var appearancePage: some View {
        VStack(spacing: 14) {
            PreferencesCard(title: "Tema", symbol: "paintpalette") {
                AppearanceModeSelector(selection: $appearanceMode)
            }
            PreferencesCard(title: "Panel görünümü", symbol: "sparkles") {
                Toggle(isOn: $liquidGlass) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Liquid Glass")
                        Text("Desteklenen macOS sürümünde Apple’ın yerel cam materyalini kullan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            PreferencesCard(title: "Önizleme", symbol: "rectangle.3.group") {
                HStack(spacing: 12) {
                    Circle().fill(Color.accentColor).frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pano kartı")
                        Text("Sakin kenarlıklar, hızlı eylemler")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "pin")
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .padding(12)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var generalPage: some View {
        VStack(spacing: 14) {
            PreferencesCard(title: "Menü çubuğu", symbol: "menubar.rectangle") {
                Text("Gobby bir menü çubuğu uygulamasıdır. Simgeye tıkladığınızda panel açılır; Dock’ta ayrı bir uygulama penceresi oluşturmaz.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Girişte Gobby’yi Aç", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            PreferencesCard(title: "Universal Clipboard", symbol: "rectangle.on.rectangle.iphone") {
                Text("Bir geçmiş kartı seçildiğinde içerik standart NSPasteboard.general üzerinden Mac’in sistem panosuna yazılır. Apple Continuity, uygun olduğunda bunu yakındaki iPhone’unuza aktarır.")
                    .font(.callout)
                RequirementRow(symbol: "checkmark.circle.fill", text: "Her iki cihazda aynı Apple Account")
                RequirementRow(symbol: "checkmark.circle.fill", text: "Wi‑Fi, Bluetooth ve Handoff açık")
                RequirementRow(symbol: "checkmark.circle.fill", text: "Cihazlar 10 metre içinde")
                Button("Mac Sistem Ayarlarını Aç") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var historyPage: some View {
        VStack(spacing: 14) {
            PreferencesCard(title: "Saklama sınırı", symbol: "archivebox") {
                Stepper("En fazla \(historyLimit) sabit olmayan öğe", value: $historyLimit, in: 50...1_000, step: 50)
                    .onChange(of: historyLimit) { _, value in
                        appState.store.setLimit(value)
                    }
                Text("Sabitlenmiş öğeler bu sınıra dahil edilmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            PreferencesCard(title: "Saklama süresi", symbol: "calendar.badge.clock") {
                Picker("Süre", selection: $historyRetentionDays) {
                    Text("Sınırsız").tag(0)
                    Text("1 gün").tag(1)
                    Text("7 gün").tag(7)
                    Text("30 gün").tag(30)
                    Text("90 gün").tag(90)
                }
                .pickerStyle(.segmented)
                .onChange(of: historyRetentionDays) { _, days in
                    appState.store.applyRetention(days: days)
                }
                Text("Sabitlenmiş öğeler süre temizliğinden her zaman korunur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            PreferencesCard(title: "Görüntüler ve OCR", symbol: "photo.badge.magnifyingglass") {
                Toggle("Görüntü geçmişini sakla", isOn: $imageHistoryEnabled)
                Toggle("Görüntülerde yerel OCR ara", isOn: $ocrEnabled)
                    .disabled(!imageHistoryEnabled)
                Text("OCR yalnızca bu Mac’te, arka planda Apple Vision ile çalışır. Görüntü veya metin hiçbir sunucuya gönderilmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            PreferencesCard(title: "Mevcut geçmiş", symbol: "chart.bar") {
                HStack(spacing: 10) {
                    StatBadge(value: "\(appState.store.items.count)", label: "toplam öğe")
                    StatBadge(value: "\(appState.store.items.filter(\.isPinned).count)", label: "sabitlenmiş")
                    StatBadge(value: "\(appState.store.items.filter { $0.kind == .image }.count)", label: "görüntü")
                }
            }
            PreferencesCard(title: "Temizlik", symbol: "trash") {
                Text("Sabitlenmemiş öğeleri ve ilişkili görüntü dosyalarını hemen kaldır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Sabitlenmemişleri Temizle", role: .destructive) {
                    clearScope = .unpinned
                    confirmClear = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var hotkeysPage: some View {
        VStack(spacing: 14) {
            PreferencesCard(title: "Panel içi klavye kontrolü", symbol: "keyboard") {
                ShortcutRow(keys: "↑ / ↓", text: "Geçmişte seçimi değiştir")
                ShortcutRow(keys: "Return", text: "Seçili öğeyi panoya yaz")
                ShortcutRow(keys: "⌘ F", text: "Aramaya odaklan")
                ShortcutRow(keys: "⌘ P", text: "Seçili öğeyi sabitle / kaldır")
                ShortcutRow(keys: "⌘ ⇧ V", text: "Düz metin olarak panoya yaz")
                ShortcutRow(keys: "Delete", text: "Seçili öğeyi sil")
                ShortcutRow(keys: "Esc", text: "Aramayı temizle, sonra paneli kapat")
            }
            PreferencesCard(title: "Global kısayollar", symbol: "globe") {
                ShortcutConfigurationView()
                .font(.caption)
                Text("Gobby, seçilen genel kısayolları yalnızca sistem tarafından kullanılabilir olduğunda kaydeder. Başka bir uygulamanın zaten kullandığı kombinasyonlar çalışmayabilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let issue = appState.hotkeyIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Genel kısayollar kaydedildi.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var privacyPage: some View {
        VStack(spacing: 14) {
            PreferencesCard(title: "Yerel ve özel", symbol: "lock") {
                Text("Gobby pano içeriğini, OCR metnini ve arama sorgularını hiçbir ağa göndermez. Geçmiş yalnızca bu Mac’in Application Support alanında saklanır.")
                    .font(.callout)
                Text("Geçici veya gizli olarak işaretlenmiş pano türleri kaydedilmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            PreferencesCard(title: "Hariç tutulan uygulamalar", symbol: "hand.raised.slash") {
                ExcludedAppsEditor()
            }
        }
    }

    private var advancedPage: some View {
        VStack(spacing: 14) {
            PreferencesCard(title: "Geçmişi temizle", symbol: "trash") {
                Text("Bu işlemler yerel verileri kaldırır ve geri alınamaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Metin Geçmişini Sil", role: .destructive) { requestClear(.text) }
                    Button("Görüntü Geçmişini Sil", role: .destructive) { requestClear(.images) }
                    Button("Tümünü Sil", role: .destructive) { requestClear(.all) }
                }
                .buttonStyle(.bordered)
            }
            PreferencesCard(title: "Gobby Stack", symbol: "square.stack.3d.up") {
                Text("Stack sırasını ve imleç konumunu temizler; pano geçmişine dokunmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Stack’i Temizle", role: .destructive) { appState.store.clearStack() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func requestClear(_ scope: ClearScope) {
        clearScope = scope
        confirmClear = true
    }

    private func performClearScope() {
        switch clearScope {
        case .unpinned:
            appState.store.clearUnpinned()
        case .text:
            appState.store.clear(categories: [.text, .link, .code, .color, .email, .phone])
        case .images:
            appState.store.clear(categories: [.image])
        case .all:
            appState.store.clear()
        case nil:
            break
        }
        clearScope = nil
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginError = "Girişte açma ayarı değiştirilemedi: \(error.localizedDescription)"
        }
    }
}

private struct PreferencesCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.065), lineWidth: 1)
        }
    }
}

private struct StatBadge: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct RequirementRow: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

private struct ShortcutRow: View {
    let keys: String
    let text: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            Text(text)
                .font(.callout)
            Spacer()
        }
    }
}

private struct AppearanceModeSelector: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 3) {
            modeButton(.automatic, symbol: "circle.lefthalf.filled")
            modeButton(.light, symbol: "sun.max.fill")
            modeButton(.dark, symbol: "moon.fill")
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.92, blendDuration: 0.06),
            value: selection
        )
    }

    private func modeButton(_ mode: AppearanceMode, symbol: String) -> some View {
        let isSelected = selection == mode.rawValue
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.92, blendDuration: 0.06)) {
                selection = mode.rawValue
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(isSelected ? 1 : 0.9)
                    .opacity(isSelected ? 1 : 0.72)
                Text(mode.title)
            }
                .font(.callout.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                            .matchedGeometryEffect(id: "appearance-selection", in: selectionNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
        .accessibilityLabel("\(mode.title) tema")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ShortcutConfigurationView: View {
    @AppStorage("gobbyOpenShortcut") private var openShortcut = "optionSpace"
    @AppStorage("gobbyPasteNextShortcut") private var pasteNextShortcut = "optionV"

    var body: some View {
        VStack(spacing: 10) {
            Picker("Gobby’yi aç", selection: $openShortcut) {
                Text("⌥ Space").tag("optionSpace")
                Text("⌥ ⇧ Space").tag("optionShiftSpace")
            }
            Picker("Sıradakini panoya kopyala", selection: $pasteNextShortcut) {
                Text("⌥ V").tag("optionV")
                Text("⌥ ⇧ V").tag("optionShiftV")
            }
        }
        .pickerStyle(.menu)
        .onChange(of: openShortcut) { _, _ in
            NotificationCenter.default.post(name: .gobbyHotkeysDidChange, object: nil)
        }
        .onChange(of: pasteNextShortcut) { _, _ in
            NotificationCenter.default.post(name: .gobbyHotkeysDidChange, object: nil)
        }
    }
}

private struct ExcludedAppsEditor: View {
    @State private var excludedBundleIdentifiers = UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if excludedBundleIdentifiers.isEmpty {
                Text("Henüz hariç tutulan uygulama yok.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(excludedBundleIdentifiers, id: \.self) { identifier in
                    HStack {
                        Image(nsImage: applicationIcon(for: identifier))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(applicationName(for: identifier))
                        Spacer()
                        Button(role: .destructive) {
                            excludedBundleIdentifiers.removeAll { $0 == identifier }
                            save()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(applicationName(for: identifier)) uygulamasını hariç tutulanlardan çıkar")
                    }
                }
            }
            Button("Uygulama Ekle…", systemImage: "plus") { chooseApplication() }
                .buttonStyle(.bordered)
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.prompt = "Ekle"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              !excludedBundleIdentifiers.contains(identifier) else { return }
        excludedBundleIdentifiers.append(identifier)
        excludedBundleIdentifiers.sort()
        save()
    }

    private func save() {
        UserDefaults.standard.set(excludedBundleIdentifiers, forKey: "excludedApps")
    }

    private func applicationName(for identifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return identifier }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func applicationIcon(for identifier: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
