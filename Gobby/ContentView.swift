import AppKit
import SwiftUI

private enum HistorySection: String, CaseIterable, Identifiable {
    case all = "Geçmiş"
    case pinned = "Sabitler"
    case calendar = "Takvim"
    case groups = "Gruplar"
    case stack = "Stack"

    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.automatic.rawValue
    @AppStorage("liquidGlass") private var liquidGlass = true
    @State private var section: HistorySection = .all
    @State private var query = ""
    @State private var categoryFilter: ClipCategory?
    @State private var selectedItemID: ClipboardItem.ID?
    @FocusState private var searchIsFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var filteredItems: [ClipboardItem] {
        let source: [ClipboardItem] = section == .pinned
            ? appState.store.items.filter(\.isPinned)
            : appState.store.items
        return source.filter { item in
            (categoryFilter == nil || item.category == categoryFilter) && item.matchesSearch(query)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
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

            VStack(spacing: 14) {
                header
                searchField
                SectionNavigation(section: $section, categoryFilter: $categoryFilter, usesGlass: usesGlass)

                if section == .all || section == .pinned {
                    listContextHeader
                }

                if section == .calendar {
                    CalendarHistoryView(query: query)
                } else if section == .groups {
                    ColorGroupsView(query: query)
                } else if section == .stack {
                    GobbyStackView()
                } else {
                    HistoryList(
                        items: filteredItems,
                        selectedItemID: $selectedItemID,
                        emptyTitle: section == .pinned ? "Henüz sabitlenmiş öğe yok" : "Pano geçmişi boş"
                    )
                }
            }
            .padding(16)

            if let toast = appState.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 390, idealWidth: 430, maxWidth: 460, minHeight: 540, idealHeight: 650, maxHeight: 700)
        .onAppear {
            selectedItemID = filteredItems.first?.id
            DispatchQueue.main.async { searchIsFocused = true }
        }
        .onChange(of: query) { _, _ in
            selectedItemID = filteredItems.first?.id
        }
        .onChange(of: section) { _, _ in
            selectedItemID = filteredItems.first?.id
            if section != .stack { searchIsFocused = true }
        }
        .onKeyPress { press in
            handleKeyPress(press)
        }
        .alert("Sabit öğe adı", isPresented: renameAlertBinding) {
            TextField("Örneğin: İş GitHub bağlantım", text: $appState.renameDraft)
            Button("Vazgeç", role: .cancel) { appState.renameItem = nil }
            Button("Kaydet") { appState.commitRename() }
        } message: {
            Text("Bu ad arama sonuçlarına da eklenir.")
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: liquidGlass)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: appState.toast)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clipboard.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Gobby")
                    .font(.headline)
                Text("\(appState.store.items.count) öğe · \(appState.store.items.filter(\.isPinned).count) sabit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { appState.showSettings() } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.borderless)
            .help("Ayarlar")
        }
    }

    private var searchField: some View {
        TextField("Geçmişte ara", text: $query)
            .textFieldStyle(.plain)
            .focused($searchIsFocused)
            .accessibilityLabel("Pano geçmişinde ara")
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                if usesGlass {
                    if #available(macOS 26.0, *) {
                        Capsule(style: .continuous)
                            .fill(.clear)
                            .glassEffect(.clear.interactive(), in: .capsule)
                    } else {
                        Capsule(style: .continuous).fill(.thinMaterial)
                    }
                } else {
                    Capsule(style: .continuous).fill(Color.primary.opacity(0.07))
                }
            }
    }

    private var listContextHeader: some View {
        HStack(spacing: 7) {
            Label(section == .pinned ? "Sabitler" : "Son kopyalananlar", systemImage: section == .pinned ? "pin.fill" : "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(filteredItems.count) öğe")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { appState.renameItem != nil },
            set: { if !$0 { appState.renameItem = nil } }
        )
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers == [.command], press.characters == "f" {
            searchIsFocused = true
            return .handled
        }
        if press.modifiers == [.command], press.characters == "p", let item = selectedItem {
            appState.store.togglePin(item)
            return .handled
        }
        if press.modifiers == [.command, .shift], press.characters == "v", let item = selectedItem {
            appState.copyAsPlainText(item)
            return .handled
        }
        switch press.key {
        case .upArrow:
            moveSelection(by: -1)
            return .handled
        case .downArrow:
            moveSelection(by: 1)
            return .handled
        case .return:
            if let item = selectedItem { appState.copy(item) }
            return selectedItem == nil ? .ignored : .handled
        case .delete, .deleteForward:
            if let item = selectedItem { appState.store.delete(item) }
            return selectedItem == nil ? .ignored : .handled
        case .escape:
            if !query.isEmpty {
                query = ""
            } else {
                NSApp.keyWindow?.orderOut(nil)
            }
            return .handled
        default:
            return .ignored
        }
    }

    private var selectedItem: ClipboardItem? {
        filteredItems.first { $0.id == selectedItemID }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        let currentIndex = selectedItemID.flatMap { id in filteredItems.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        selectedItemID = filteredItems[nextIndex].id
    }
}

private struct SectionNavigation: View {
    @Binding var section: HistorySection
    @Binding var categoryFilter: ClipCategory?
    let usesGlass: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(HistorySection.allCases) { item in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { section = item }
                        } label: {
                            Label(item.rawValue, systemImage: symbol(for: item))
                                .font(.caption.weight(section == item ? .semibold : .medium))
                                .foregroundStyle(section == item ? Color.primary : Color.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background {
                                    if section == item {
                                        Capsule(style: .continuous)
                                            .fill(Color.accentColor.opacity(0.18))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.rawValue)
                    }
                }
                .padding(3)
            }
            .background {
                if usesGlass {
                    if #available(macOS 26.0, *) {
                        Capsule(style: .continuous)
                            .fill(.clear)
                            .glassEffect(.regular, in: .capsule)
                    } else {
                        Capsule(style: .continuous).fill(.thinMaterial)
                    }
                } else {
                    Capsule(style: .continuous).fill(Color.primary.opacity(0.055))
                }
            }

            Menu {
                Button("Tüm kategoriler") { categoryFilter = nil }
                Divider()
                ForEach(ClipCategory.allCases) { category in
                    Button {
                        categoryFilter = category
                    } label: {
                        Label(category.label, systemImage: category.symbol)
                    }
                }
            } label: {
                Image(systemName: categoryFilter?.symbol ?? "line.3.horizontal.decrease.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(categoryFilter == nil ? Color.secondary : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .help(categoryFilter?.label ?? "Kategorilere göre filtrele")
        }
    }

    private func symbol(for section: HistorySection) -> String {
        switch section {
        case .all: return "clock"
        case .pinned: return "pin"
        case .calendar: return "calendar"
        case .groups: return "circle.grid.2x2"
        case .stack: return "square.stack.3d.up"
        }
    }
}

private struct HistoryList: View {
    @EnvironmentObject private var appState: AppState
    let items: [ClipboardItem]
    @Binding var selectedItemID: ClipboardItem.ID?
    let emptyTitle: String

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "clipboard")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(items) { item in
                            ClipboardRow(item: item, isSelected: item.id == selectedItemID)
                                .simultaneousGesture(TapGesture().onEnded { selectedItemID = item.id })
                        }
                    }
                    .padding(.vertical, 1)
                }
                .closesOpenSwipeActionsOnVerticalScroll()
            }
        }
    }
}

private struct GobbyStackView: View {
    @EnvironmentObject private var appState: AppState

    private var entries: [(entry: GobbyStackEntry, item: ClipboardItem)] {
        appState.store.stackItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let next = appState.store.nextStackItem {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Sıradaki", systemImage: "arrow.right.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                        Spacer()
                        Text("\(appState.store.stackCursor + 1) / \(entries.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(next.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(next.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Button("Sıradakini Panoya Kopyala", systemImage: "doc.on.clipboard") {
                        appState.pasteNextStackItem()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Başa Sar", systemImage: "backward.end") { appState.store.restartStack() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Temizle", systemImage: "trash", role: .destructive) { appState.store.clearStack() }
                        .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView {
                    Label("Gobby Stack boş", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Geçmişte bir öğeye sağ tıklayıp “Gobby Stack’e Ekle”yi seçin.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !entries.isEmpty {
                HStack {
                    Text("Kuyruk")
                        .font(.headline)
                    Text("\(entries.count) öğe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Sürükleyerek sırala")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                List {
                    ForEach(entries, id: \.entry.id) { pair in
                        HStack(spacing: 10) {
                            Text("\(stackPosition(for: pair.entry) + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Image(systemName: pair.item.category.symbol)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.item.title).lineLimit(1)
                                Text(pair.item.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                appState.store.removeFromStack(pair.entry)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onMove(perform: appState.store.moveStackEntries)
                }
                .listStyle(.plain)
            }
        }
    }

    private func stackPosition(for entry: GobbyStackEntry) -> Int {
        entries.firstIndex(where: { $0.entry.id == entry.id }) ?? 0
    }
}

private enum GroupsLayout: String, CaseIterable, Identifiable {
    case list
    case icons

    var id: String { rawValue }
}

private struct ClipboardColorGroup: Identifiable {
    let id: String
    let title: String
    let color: Color?
    let items: [ClipboardItem]
}

private struct ColorGroupsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("groupsLayout") private var layoutRaw = GroupsLayout.list.rawValue
    @State private var selectedGroupID: String?
    let query: String

    private var layout: Binding<GroupsLayout> {
        Binding(
            get: { GroupsLayout(rawValue: layoutRaw) ?? .list },
            set: { layoutRaw = $0.rawValue }
        )
    }

    private var matchingItems: [ClipboardItem] {
        appState.store.items.filter { item in
            item.matchesSearch(query)
        }
    }

    private var groups: [ClipboardColorGroup] {
        var result: [ClipboardColorGroup] = []
        for color in ClipColor.allCases where color != .custom {
            let items = matchingItems.filter { $0.tagColor == color }
            if !items.isEmpty {
                result.append(ClipboardColorGroup(id: color.rawValue, title: color.title, color: color.uiColor, items: items))
            }
        }

        let customItems = matchingItems.filter { $0.tagColor == .custom }
        let customGroups = Dictionary(grouping: customItems) { $0.customColorHex ?? "custom" }
        for hex in customGroups.keys.sorted() {
            let items = customGroups[hex] ?? []
            result.append(ClipboardColorGroup(id: "custom-\(hex)", title: "Özel renk", color: Color(hex: hex), items: items))
        }

        let uncolored = matchingItems.filter { $0.tagColor == nil }
        if !uncolored.isEmpty {
            result.append(ClipboardColorGroup(id: "uncolored", title: "Renksiz", color: nil, items: uncolored))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Renk grupları")
                    .font(.headline)
                Spacer()
                Picker("Görünüm", selection: layout) {
                    Image(systemName: "list.bullet").tag(GroupsLayout.list)
                    Image(systemName: "square.grid.2x2").tag(GroupsLayout.icons)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 92)
            }

            if groups.isEmpty {
                ContentUnavailableView("Gruplanacak öğe yok", systemImage: "circle.grid.2x2")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if layout.wrappedValue == .list {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            ColorGroupSection(group: group)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .closesOpenSwipeActionsOnVerticalScroll()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(groups) { group in
                                Button {
                                    selectedGroupID = selectedGroupID == group.id ? nil : group.id
                                } label: {
                                    VStack(spacing: 7) {
                                        Image(systemName: group.color == nil ? "circle.dashed" : "circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(group.color ?? .secondary)
                                        Text(group.title)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                        Text("\(group.items.count) öğe")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 86)
                                    .background(selectedGroupID == group.id ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let selectedGroup = groups.first(where: { $0.id == selectedGroupID }) {
                            ColorGroupSection(group: selectedGroup)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .closesOpenSwipeActionsOnVerticalScroll()
            }
        }
    }
}

private struct ColorGroupSection: View {
    let group: ClipboardColorGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(group.color ?? Color.secondary.opacity(0.35))
                    .frame(width: 10, height: 10)
                Text(group.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(group.items.count) öğe")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background((group.color ?? Color.primary).opacity(0.09), in: Capsule(style: .continuous))
            ForEach(group.items) { item in ClipboardRow(item: item) }
        }
    }
}

private struct ClipColorPicker: View {
    @EnvironmentObject private var appState: AppState
    let item: ClipboardItem
    @Binding var isPresented: Bool
    @State private var customColor: Color
    @State private var isInlinePaletteVisible = false

    init(item: ClipboardItem, isPresented: Binding<Bool>) {
        self.item = item
        _isPresented = isPresented
        _customColor = State(initialValue: item.uiTagColor ?? .blue)
    }

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Renk ata")
                    .font(.headline)
                Spacer()
                Button("Kaldır") {
                    appState.store.setColor(nil, for: item)
                    isPresented = false
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ClipColor.allCases.filter { $0 != .custom }) { color in
                    Button {
                        appState.store.setColor(color, for: item)
                        isPresented = false
                    } label: {
                        Circle()
                            .fill(color.uiColor)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if item.tagColor == color {
                                    Circle().strokeBorder(.white, lineWidth: 3)
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .shadow(color: color.uiColor.opacity(0.45), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help(color.title)
                }
            }
            Divider()
            Button {
                withAnimation(.snappy) { isInlinePaletteVisible.toggle() }
            } label: {
                HStack {
                    Text("Özel renk")
                        .foregroundStyle(.primary)
                    Spacer()
                    RoundedRectangle(cornerRadius: 6)
                        .fill(customColor)
                        .frame(width: 30, height: 20)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    Image(systemName: isInlinePaletteVisible ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isInlinePaletteVisible {
                InlineColorSpectrum(selection: $customColor)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Button("Özel rengi uygula") {
                appState.store.setCustomColor(hex: customColor.hexString, for: item)
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(width: 220)
    }
}

private struct InlineColorSpectrum: View {
    @Binding var selection: Color
    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    @State private var hexCode: String

    init(selection: Binding<Color>) {
        _selection = selection
        let color = NSColor(selection.wrappedValue).usingColorSpace(.sRGB) ?? .systemBlue
        var initialHue: CGFloat = 0
        var initialSaturation: CGFloat = 0
        var initialBrightness: CGFloat = 0
        var initialAlpha: CGFloat = 1
        color.getHue(&initialHue, saturation: &initialSaturation, brightness: &initialBrightness, alpha: &initialAlpha)
        _hue = State(initialValue: Double(initialHue))
        _saturation = State(initialValue: Double(initialSaturation))
        _brightness = State(initialValue: Double(initialBrightness))
        _hexCode = State(initialValue: Color(nsColor: color).hexString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Spektrum")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(.white, lineWidth: 2)
                            .shadow(color: .black.opacity(0.55), radius: 1)
                            .frame(width: 15, height: 15)
                            .position(x: saturation * width, y: (1 - brightness) * height)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                saturation = min(max(Double(value.location.x / width), 0), 1)
                                brightness = min(max(1 - Double(value.location.y / height), 0), 1)
                                updateSelection()
                            }
                    )
            }
            .frame(height: 118)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let hueGradient = LinearGradient(
                    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hueGradient)
                    .overlay {
                        Capsule()
                            .fill(.white)
                            .frame(width: 4, height: 20)
                            .shadow(color: .black.opacity(0.55), radius: 1)
                            .position(x: hue * width, y: 11)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                hue = min(max(Double(value.location.x / width), 0), 1)
                                updateSelection()
                            }
                    )
            }
            .frame(height: 22)

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selection)
                    .frame(width: 32, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.4), lineWidth: 1))
                Text("#")
                    .foregroundStyle(.secondary)
                TextField("Renk kodu", text: $hexCode)
                    .textFieldStyle(.roundedBorder)
                    .fontDesign(.monospaced)
                    .onSubmit { updateFromHex() }
                    .onChange(of: hexCode) { _, newValue in
                        updateFromHex(newValue)
                    }
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    private func updateSelection() {
        selection = Color(hue: hue, saturation: saturation, brightness: brightness)
        hexCode = selection.hexString
    }

    private func updateFromHex(_ value: String? = nil) {
        let input = value ?? hexCode
        guard let parsed = Color(hex: input) else { return }
        selection = parsed
        let color = NSColor(parsed).usingColorSpace(.sRGB) ?? .systemBlue
        var parsedHue: CGFloat = 0
        var parsedSaturation: CGFloat = 0
        var parsedBrightness: CGFloat = 0
        var alpha: CGFloat = 1
        color.getHue(&parsedHue, saturation: &parsedSaturation, brightness: &parsedBrightness, alpha: &alpha)
        hue = Double(parsedHue)
        saturation = Double(parsedSaturation)
        brightness = Double(parsedBrightness)
        let normalized = parsed.hexString
        if hexCode != normalized { hexCode = normalized }
    }
}

private extension ClipColor {
    var uiColor: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .custom: return .gray
        }
    }
}

private extension ClipboardItem {
    var uiTagColor: Color? {
        guard let tagColor else { return nil }
        if tagColor == .custom {
            return customColorHex.flatMap(Color.init(hex:)) ?? .gray
        }
        return tagColor.uiColor
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.systemBlue
        return String(format: "%02X%02X%02X", Int(nsColor.redComponent * 255), Int(nsColor.greenComponent * 255), Int(nsColor.blueComponent * 255))
    }
}

struct ClipboardRow: View {
    @EnvironmentObject private var appState: AppState
    let item: ClipboardItem
    var isSelected = false
    @State private var swipeOffset: CGFloat = 0
    @State private var isDeleting = false
    @State private var smokeExpanded = false
    @State private var isColorPickerPresented = false
    @State private var isImagePreviewPresented = false
    @State private var isHovered = false
    @State private var dragAxis: RowDragAxis?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let actionWidth: CGFloat = 66

    var body: some View {
        ZStack(alignment: .leading) {
            if swipeOffset > 1 {
                HStack(spacing: 0) {
                    SwipeActionTray(symbol: "trash.fill", tint: .red, label: "Geçmişten sil") { removeItem() }
                        .frame(width: actionWidth)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
            }

            if swipeOffset < -1 {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SwipeActionTray(
                        symbol: item.isPinned ? "pin.slash.fill" : "pin.fill",
                        tint: .orange,
                        label: item.isPinned ? "Sabitlemeyi kaldır" : "Sabitle"
                    ) {
                        appState.store.togglePin(item)
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { swipeOffset = 0 }
                    }
                    .frame(width: actionWidth)
                }
                .padding(.vertical, 3)
            }

            HStack(alignment: .top, spacing: 12) {
                Button { appState.copy(item) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        preview
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                if item.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            if item.kind != .image {
                                Text(item.preview)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            HStack(spacing: 5) {
                                Label(item.category.label, systemImage: item.category.symbol)
                                if let sourceAppName = item.sourceAppName {
                                    Text("•")
                                    Text(sourceAppName)
                                        .lineLimit(1)
                                }
                                Text("•")
                                Text(item.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(deleteSwipe)

                Spacer(minLength: 8)
                VStack(spacing: 7) {
                    if item.kind == .image {
                        Button {
                            isImagePreviewPresented = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.borderless)
                        .help("Büyük önizleme")
                        .popover(isPresented: $isImagePreviewPresented) {
                            ImagePreview(item: item)
                                .environmentObject(appState)
                        }
                    }
                    Button {
                        isColorPickerPresented = true
                    } label: {
                        Circle()
                            .fill(item.uiTagColor ?? Color.secondary.opacity(0.36))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    }
                    .buttonStyle(.borderless)
                    .help("Renk ata")
                    .popover(isPresented: $isColorPickerPresented, arrowEdge: .trailing) {
                        ClipColorPicker(item: item, isPresented: $isColorPickerPresented)
                            .environmentObject(appState)
                    }

                    Button {
                        appState.store.togglePin(item)
                    } label: {
                        Image(systemName: item.isPinned ? "pin.slash" : "pin")
                    }
                    .buttonStyle(.borderless)
                    .help(item.isPinned ? "Sabitlemeyi kaldır" : "Sabitle")

                    Button(role: .destructive) {
                        removeItem()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Geçmişten sil")
                }
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : (isHovered ? Color.primary.opacity(0.07) : .clear))
            }
            .offset(x: swipeOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .gobbyRowsShouldCloseSwipeActions)) { _ in
            guard swipeOffset != 0, !isDeleting else { return }
            swipeOffset = 0
        }
        .opacity(isDeleting ? 0.08 : 1)
        .scaleEffect(isDeleting ? 0.96 : 1)
        .overlay {
            if isDeleting {
                SmokeDissolve(expanded: smokeExpanded)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isDeleting)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: swipeOffset)
        .contextMenu {
            Button("Panoya Kopyala", systemImage: "doc.on.clipboard") { appState.copy(item) }
            Button("Düz Metin Olarak Kopyala", systemImage: "text.plaintext") { appState.copyAsPlainText(item) }
            Button(item.isPinned ? "Sabitlemeyi Kaldır" : "Sabitle", systemImage: item.isPinned ? "pin.slash" : "pin") {
                appState.store.togglePin(item)
            }
            Button("Sabit öğe adını düzenle", systemImage: "pencil") { appState.requestRename(item) }
            Button("Gobby Stack’e Ekle", systemImage: "square.stack.3d.up") { appState.store.addToStack(item) }
            Divider()
            Button("Geçmişten Sil", systemImage: "trash", role: .destructive) { removeItem() }
        }
    }

    private var deleteSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragAxis == nil,
                   max(abs(value.translation.width), abs(value.translation.height)) > 5 {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                guard dragAxis == .horizontal else { return }
                if value.translation.width > 0 {
                    swipeOffset = min(value.translation.width, actionWidth)
                } else {
                    swipeOffset = max(value.translation.width, -actionWidth)
                }
            }
            .onEnded { value in
                defer { dragAxis = nil }
                guard dragAxis == .horizontal else {
                    if swipeOffset != 0 {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { swipeOffset = 0 }
                    }
                    return
                }
                if value.translation.width >= 82 {
                    removeItem()
                } else if value.translation.width >= 44 {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { swipeOffset = actionWidth }
                } else if value.translation.width <= -45 {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { swipeOffset = -actionWidth }
                } else {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { swipeOffset = 0 }
                }
            }
    }

    private func removeItem() {
        guard !isDeleting else { return }
        if reduceMotion {
            appState.store.delete(item)
            return
        }
        withAnimation(.easeOut(duration: 0.16)) { isDeleting = true }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.36)) { smokeExpanded = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { appState.store.delete(item) }
    }

    @ViewBuilder
    private var preview: some View {
        if item.kind == .image, let image = appState.store.thumbnail(for: item) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: item.kind.symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

private enum RowDragAxis {
    case horizontal
    case vertical
}

private struct SwipeActionTray: View {
    let symbol: String
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.16), in: Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct ImagePreview: View {
    @EnvironmentObject private var appState: AppState
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = appState.store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 520, maxHeight: 360)
            }
            HStack {
                Label(item.imageFormat ?? "Görüntü", systemImage: "photo")
                if let width = item.imageWidth, let height = item.imageHeight {
                    Text("\(width) × \(height)")
                }
                Spacer()
                Text(item.createdAt, format: .dateTime.day().month().hour().minute())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

private struct SmokeDissolve: View {
    let expanded: Bool
    private let particles: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (-36, -20, 38), (30, -24, 28), (-48, 12, 30), (44, 16, 42),
        (-15, 30, 34), (17, -36, 24), (58, -4, 25), (-60, -8, 22)
    ]

    var body: some View {
        ZStack {
            ForEach(particles.indices, id: \.self) { index in
                let particle = particles[index]
                Circle()
                    .fill(.white.opacity(expanded ? 0 : 0.28))
                    .frame(width: expanded ? particle.size * 1.55 : particle.size * 0.45, height: expanded ? particle.size * 1.55 : particle.size * 0.45)
                    .blur(radius: expanded ? 13 : 5)
                    .offset(x: expanded ? particle.x : 0, y: expanded ? particle.y : 0)
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let appearance: NSAppearance?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = appearance
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.appearance = appearance
    }
}

struct NativeWindowBackground: View {
    var body: some View {
        Rectangle().fill(Color(nsColor: .windowBackgroundColor))
    }
}

struct WindowAppearanceSynchronizer: NSViewRepresentable {
    let appearance: NSAppearance?

    func makeNSView(context: Context) -> WindowAppearanceSynchronizerView {
        WindowAppearanceSynchronizerView(appearance: appearance)
    }

    func updateNSView(_ nsView: WindowAppearanceSynchronizerView, context: Context) {
        nsView.appearanceOverride = appearance
    }
}

final class WindowAppearanceSynchronizerView: NSView {
    var appearanceOverride: NSAppearance? {
        didSet { applyAppearance() }
    }

    init(appearance: NSAppearance?) {
        appearanceOverride = appearance
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }

    private func applyAppearance() {
        guard let window, window.appearance?.name != appearanceOverride?.name else { return }
        window.appearance = appearanceOverride
    }
}

extension View {
    func closesOpenSwipeActionsOnVerticalScroll() -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width),
                          abs(value.translation.height) > 7 else { return }
                    NotificationCenter.default.post(name: .gobbyRowsShouldCloseSwipeActions, object: nil)
                }
        )
    }
}
