import SwiftUI
import Observation

// MARK: - Tabs

nonisolated enum TabKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case home, library, playlists, albums, artists, songs, downloads, favorites, radio, queue, recentlyPlayed, audioLab, files, shortcut
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .playlists: "Playlists"
        case .albums: "Albums"
        case .artists: "Artists"
        case .songs: "Songs"
        case .downloads: "Downloads"
        case .favorites: "Favorites"
        case .radio: "Radio"
        case .queue: "Queue"
        case .recentlyPlayed: "Recently Played"
        case .audioLab: "Sound"
        case .files: "Files"
        case .shortcut: "Shortcut"
        }
    }
    var icon: String {
        switch self {
        case .home: "house"
        case .library: "music.note"
        case .playlists: "music.note.list"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .songs: "music.quarternote.3"
        case .downloads: "arrow.down.circle"
        case .favorites: "star"
        case .radio: "dot.radiowaves.left.and.right"
        case .queue: "list.bullet"
        case .recentlyPlayed: "clock"
        case .audioLab: "slider.vertical.3"
        case .files: "shippingbox"
        case .shortcut: "bolt"
        }
    }
}

nonisolated struct TabItemConfig: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var kind: TabKind
    var title: String
    var icon: String
    var targetKind: LibraryEntry.Kind?
    var targetKey: String?

    init(kind: TabKind, title: String? = nil, icon: String? = nil, targetKind: LibraryEntry.Kind? = nil, targetKey: String? = nil) {
        self.id = kind == .shortcut ? UUID().uuidString : kind.rawValue
        self.kind = kind
        self.title = title ?? kind.title
        self.icon = icon ?? kind.icon
        self.targetKind = targetKind
        self.targetKey = targetKey
    }

    var appTab: AppTab {
        switch kind {
        case .home: .home
        case .library: .library
        default: .custom(id)
        }
    }
}

extension TabItemConfig {
    @ViewBuilder var rootView: some View {
        switch kind {
        case .home: HomeView()
        case .library: LibraryView()
        case .playlists: PlaylistsView().themedBackground()
        case .albums: AlbumsView().themedBackground()
        case .artists: ArtistsView().themedBackground()
        case .songs: SongsView().themedBackground()
        case .downloads: DownloadsView().themedBackground()
        case .favorites: FavoritesView().themedBackground()
        case .radio: RadioView().themedBackground()
        case .queue: QueueTabView()
        case .recentlyPlayed: RecentlyPlayedView().themedBackground()
        case .audioLab: StudioView().themedBackground()
        case .files: FilesView().themedBackground()
        case .shortcut:
            if let k = targetKind, let key = targetKey { CollectionDetailView(kind: k, key: key).themedBackground() }
            else { ContentUnavailableView("Nothing Here", systemImage: "bolt") }
        }
    }
}

// MARK: - Home sections & shortcuts

nonisolated enum HomeSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case topPicks, suggested, shortcuts, recentlyPlayed, madeForYou, artists, recentlyAdded, favorites, playlists, downloads, streaming
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topPicks: "Top Picks"
        case .suggested: "Suggested for You"
        case .shortcuts: "Shortcuts"
        case .recentlyPlayed: "Recently Played"
        case .madeForYou: "Made for You"
        case .artists: "Artists"
        case .recentlyAdded: "Recently Added"
        case .favorites: "Favorite Songs"
        case .playlists: "Playlists"
        case .downloads: "On This iPhone"
        case .streaming: "From Your Server"
        }
    }
}

nonisolated struct HomeSectionConfig: Codable, Hashable, Identifiable, Sendable {
    var section: HomeSection
    var visible: Bool
    var id: String { section.rawValue }
}

nonisolated struct HomeShortcut: Codable, Hashable, Identifiable, Sendable {
    enum Action: String, Codable, CaseIterable, Identifiable, Sendable {
        case shuffleAll, smartShuffle, favorites, downloads, recentlyAdded, station, sleep30, audioLab, openEntry
        var id: String { rawValue }
        var title: String {
            switch self {
            case .shuffleAll: "Shuffle All"
            case .smartShuffle: "Smart Shuffle"
            case .favorites: "Play Favorites"
            case .downloads: "Play Downloads"
            case .recentlyAdded: "Recently Added"
            case .station: "Surprise Station"
            case .sleep30: "Sleep in 30 min"
            case .audioLab: "Sound"
            case .openEntry: "Open…"
            }
        }
        var icon: String {
            switch self {
            case .shuffleAll: "shuffle"
            case .smartShuffle: "sparkles"
            case .favorites: "star.fill"
            case .downloads: "arrow.down.circle.fill"
            case .recentlyAdded: "clock.badge.checkmark"
            case .station: "dot.radiowaves.left.and.right"
            case .sleep30: "moon.zzz.fill"
            case .audioLab: "slider.vertical.3"
            case .openEntry: "arrow.up.right.square"
            }
        }
    }
    var id = UUID()
    var action: Action
    var title: String
    var icon: String
    var entryKind: LibraryEntry.Kind?
    var entryKey: String?
}

@Observable
final class LayoutStore {
    static let shared = LayoutStore()

    var tabs: [TabItemConfig] { didSet { if !adoptingTheme { tabsCustomized = true }; save() } }
    var searchEnabled: Bool { didSet { if !adoptingTheme { tabsCustomized = true }; save() } }
    /// You set up the tab bar yourself: themes no longer replace it (until "Reset" in the tab editor).
    private(set) var tabsCustomized: Bool
    @ObservationIgnored private var adoptingTheme = false
    var homeSections: [HomeSectionConfig] { didSet { save() } }
    var shortcuts: [HomeShortcut] { didSet { save() } }

    static let defaultTabs = [TabItemConfig(kind: .home), TabItemConfig(kind: .library)]
    static let defaultSections: [HomeSectionConfig] = HomeSection.allCases.map {
        HomeSectionConfig(section: $0, visible: [.topPicks, .suggested, .recentlyPlayed, .madeForYou, .artists, .recentlyAdded].contains($0))
    }
    static let defaultShortcuts: [HomeShortcut] = [.shuffleAll, .favorites, .smartShuffle, .sleep30].map {
        HomeShortcut(action: $0, title: $0.title, icon: $0.icon)
    }

    private struct Stored: Codable {
        var tabs: [TabItemConfig]
        var searchEnabled: Bool
        var homeSections: [HomeSectionConfig]
        var shortcuts: [HomeShortcut]
        var tabsCustomized: Bool?
    }

    private init() {
        let s = UserDefaults.standard.data(forKey: "layout").flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        let tabs = (s?.tabs.isEmpty == false ? s?.tabs : nil) ?? Self.defaultTabs
        let search = s?.searchEnabled ?? true
        self.tabs = tabs
        searchEnabled = search
        // Saved before this was tracked: a tab bar no built-in theme has is one you made.
        tabsCustomized = s?.tabsCustomized
            ?? !AppTheme.builtIns.contains { $0.tabs == tabs && ($0.searchTab ?? true) == search }
        var sections = s?.homeSections ?? Self.defaultSections
        for d in Self.defaultSections where !sections.contains(where: { $0.section == d.section }) {
            if d.section == .suggested {
                // New for everyone: show it right below Top Picks (it hides itself without a module connection).
                let at = sections.firstIndex { $0.section == .topPicks }.map { $0 + 1 } ?? 0
                sections.insert(HomeSectionConfig(section: .suggested, visible: true), at: at)
            } else {
                sections.append(HomeSectionConfig(section: d.section, visible: false))
            }
        }
        homeSections = sections
        shortcuts = s?.shortcuts ?? Self.defaultShortcuts
    }

    /// A theme you switch to brings its tab bar, unless you've arranged your own.
    func adoptTabs(of theme: AppTheme) {
        guard !tabsCustomized, let themeTabs = theme.tabs, !themeTabs.isEmpty else { return }
        adoptingTheme = true
        defer { adoptingTheme = false }
        if tabs != themeTabs { tabs = themeTabs }
        if searchEnabled != (theme.searchTab ?? true) { searchEnabled = theme.searchTab ?? true }
    }

    /// Exactly two tabs plus search keeps MRSC's own floating "+" and search pills around the bar.
    var usesClassicBar: Bool { tabs.count == 2 && searchEnabled }
    var visibleSections: [HomeSection] { homeSections.filter(\.visible).map(\.section) }

    func resetTabs() {
        tabs = Self.defaultTabs
        searchEnabled = true
        tabsCustomized = false
        save()
    }
    func resetHome() { homeSections = Self.defaultSections; shortcuts = Self.defaultShortcuts }

    private func save() {
        let s = Stored(tabs: tabs, searchEnabled: searchEnabled, homeSections: homeSections, shortcuts: shortcuts, tabsCustomized: tabsCustomized)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "layout") }
    }
}

// MARK: - Editors

struct CustomizeView: View {
    @Environment(LayoutStore.self) private var layout
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @State private var editing: AppTheme?
    @State private var editingPlayer: AppTheme?

    var body: some View {
        List {
            Section {
                NavigationLink { ThemesView() } label: {
                    HStack(spacing: 14) {
                        GradientIcon(symbol: "paintpalette.fill", colors: [.orange, .pink], size: 32)
                        Text("Themes")
                        Spacer()
                        Text(ThemeStore.shared.selected.name).foregroundStyle(.secondary)
                    }
                }
                Button {
                    // Your own theme is edited in place; a built-in one is copied first.
                    let current = ThemeStore.shared.current
                    editing = current.builtIn ? ThemeStore.shared.duplicate(current) : current
                } label: {
                    HStack(spacing: 14) {
                        GradientIcon(symbol: "paintbrush.pointed.fill", colors: [.purple, .blue], size: 32)
                        Text("Colors, Fonts, Player & Lyrics")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            } footer: { Text("Colors, background, blur, transparency, glass, corner radius, fonts, icons, animations, player layout, album-art size, queue, mini player and lyrics are all part of a theme.") }

            Section {
                NavigationLink { StartupSettingsView() } label: {
                    HStack(spacing: 14) {
                        GradientIcon(symbol: "scribble.variable", colors: [.red, .orange], size: 32)
                        Text("Startup & App Icon")
                        Spacer()
                        Text(BrandStyle.current.name).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink { TabsEditor() } label: {
                    HStack(spacing: 14) {
                        GradientIcon(symbol: "dock.rectangle", colors: [.teal, .green], size: 32)
                        Text("Tab Bar")
                        Spacer()
                        Text(layout.tabs.map(\.title).joined(separator: " | ")).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Button {
                    if player.current != nil {
                        // Customizing happens on the real player: close Settings, open the player in edit mode.
                        router.editPlayerOnOpen = true
                        router.showSettings = false
                        Task { try? await Task.sleep(for: .milliseconds(450)); router.showPlayer = true }
                    } else {
                        let current = ThemeStore.shared.current
                        editingPlayer = current.builtIn ? ThemeStore.shared.duplicate(current) : current
                    }
                } label: {
                    HStack(spacing: 14) {
                        GradientIcon(symbol: "play.rectangle.fill", colors: [.red, .orange], size: 32)
                        Text("Music Player")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
                NavigationLink { WidgetCustomizer() } label: {
                    HStack(spacing: 14) {
                        GradientIcon(symbol: "square.grid.2x2.fill", colors: [.indigo, .cyan], size: 32)
                        Text("Widgets")
                    }
                }
                NavigationLink { HomeEditor() } label: {
                    HStack(spacing: 14) {
                        GradientIcon(symbol: "house.fill", colors: [.pink, .red], size: 32)
                        Text("Home Screen")
                    }
                }
            }
        }
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { ThemeEditor(theme: $0) }
        .sheet(item: $editingPlayer) { PlayerLayoutSheet(theme: $0) }
    }
}

struct TabsEditor: View {
    @Environment(LayoutStore.self) private var layout
    @Environment(LibraryStore.self) private var library
    @State private var editing: TabItemConfig?
    @State private var pickingShortcut = false

    private var available: [TabKind] {
        TabKind.allCases.filter { k in k != .shortcut && !layout.tabs.contains { $0.kind == k } }
    }

    var body: some View {
        @Bindable var layout = layout
        List {
            Section {
                ForEach(layout.tabs) { tab in
                    Button { editing = tab } label: {
                        HStack(spacing: 14) {
                            Image(systemName: tab.icon).frame(width: 28).foregroundStyle(Theme.accent)
                            Text(tab.title)
                            Spacer()
                            if tab.kind == .shortcut { Text("Shortcut").font(.caption).foregroundStyle(.secondary) }
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                    .deleteDisabled(layout.tabs.count <= 1)
                }
                .onMove { layout.tabs.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { if layout.tabs.count > 1 { layout.tabs.remove(atOffsets: $0) } }
                if layout.tabs.count < 5 {
                    Menu {
                        ForEach(available) { k in
                            Button { withAnimation { layout.tabs.append(TabItemConfig(kind: k)) } } label: { Label(k.title, systemImage: k.icon) }
                        }
                        Divider()
                        Button { pickingShortcut = true } label: { Label("Shortcut to Playlist, Album or Artist…", systemImage: "bolt") }
                    } label: { Label("Add Tab", systemImage: "plus") }
                }
            } header: { Text("Tabs") } footer: { Text("Up to five tabs. Drag to reorder, swipe to remove, tap to rename or change the icon.") }

            Section {
                Toggle(isOn: $layout.searchEnabled.animation()) { Label("Search", systemImage: "magnifyingglass") }
            } footer: {
                Text(layout.usesClassicBar
                     ? "With two tabs and search, MRSC shows its floating + and search buttons next to the tab bar."
                     : "This layout uses the standard iOS tab bar with a separate search tab. Import options are in Library.")
            }

            Section { Button("Reset to Home | Library | Search") { withAnimation { layout.resetTabs() } } }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tab Bar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { tab in
            TabItemEditor(tab: tab) { updated in
                if let i = layout.tabs.firstIndex(where: { $0.id == updated.id }) { layout.tabs[i] = updated }
            }
        }
        .sheet(isPresented: $pickingShortcut) {
            EntryPicker(title: "Add Shortcut Tab") { entry in
                layout.tabs.append(TabItemConfig(kind: .shortcut, title: entry.title,
                                                 icon: entry.kind == .artist ? "music.mic" : entry.kind == .album ? "square.stack" : "music.note.list",
                                                 targetKind: entry.kind, targetKey: entry.key))
            }
        }
    }
}

struct TabItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var tab: TabItemConfig
    var save: (TabItemConfig) -> Void

    static let icons = ["house", "music.note", "music.note.list", "square.stack", "music.mic", "music.quarternote.3", "arrow.down.circle",
                        "star", "heart", "dot.radiowaves.left.and.right", "list.bullet", "clock", "slider.vertical.3", "shippingbox",
                        "bolt", "sparkles", "headphones", "guitars", "pianokeys", "waveform", "flame", "moon.stars", "sun.max",
                        "leaf", "car", "figure.run", "books.vertical", "opticaldisc", "hifispeaker", "airpodsmax", "music.microphone"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Name", text: $tab.title) }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(Self.icons, id: \.self) { icon in
                            Button { tab.icon = icon } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 20))
                                    .frame(width: 44, height: 44)
                                    .background(tab.icon == icon ? Theme.accent.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(tab.icon == icon ? Theme.accent : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section { Button("Restore Default Name & Icon") { tab.title = tab.kind == .shortcut ? tab.title : tab.kind.title; tab.icon = tab.kind.icon } }
            }
            .navigationTitle("Edit Tab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(tab); dismiss() }.disabled(tab.title.isEmpty) }
            }
        }
    }
}

struct HomeEditor: View {
    @Environment(LayoutStore.self) private var layout
    @State private var addingEntryShortcut = false

    var body: some View {
        @Bindable var layout = layout
        List {
            Section {
                ForEach($layout.homeSections) { $s in
                    Toggle(s.section.title, isOn: $s.visible)
                }
                .onMove { layout.homeSections.move(fromOffsets: $0, toOffset: $1) }
            } header: { Text("Sections") } footer: { Text("Drag to reorder, switch off what you don't need. Suggested for You also decides whether Search suggests songs. Without a connection, Home and Search only show music on this iPhone.") }

            Section {
                ForEach(layout.shortcuts) { s in
                    Label(s.title, systemImage: s.icon)
                }
                .onMove { layout.shortcuts.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { layout.shortcuts.remove(atOffsets: $0) }
                Menu {
                    ForEach(HomeShortcut.Action.allCases.filter { $0 != .openEntry }) { a in
                        Button { layout.shortcuts.append(HomeShortcut(action: a, title: a.title, icon: a.icon)) } label: { Label(a.title, systemImage: a.icon) }
                    }
                    Divider()
                    Button { addingEntryShortcut = true } label: { Label("Playlist, Album or Artist…", systemImage: "arrow.up.right.square") }
                } label: { Label("Add Shortcut", systemImage: "plus") }
            } header: { Text("Shortcuts") } footer: { Text("Shown in the Shortcuts section on Home.") }

            Section { Button("Reset Home Screen") { withAnimation { layout.resetHome() } } }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Home Screen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingEntryShortcut) {
            EntryPicker(title: "Add Shortcut") { e in
                layout.shortcuts.append(HomeShortcut(action: .openEntry, title: e.title,
                                                     icon: e.kind == .artist ? "music.mic" : e.kind == .album ? "square.stack.fill" : "music.note.list",
                                                     entryKind: e.kind, entryKey: e.key))
                if let i = layout.homeSections.firstIndex(where: { $0.section == .shortcuts }) { layout.homeSections[i].visible = true }
            }
        }
    }
}

/// Picks a playlist, album or artist.
struct EntryPicker: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let title: String
    var pick: (LibraryEntry) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                section("Playlists", library.playlistEntries)
                section("Albums", library.albumEntries)
                section("Artists", library.artistEntries)
            }
            .searchable(text: $query)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    @ViewBuilder private func section(_ name: String, _ entries: [LibraryEntry]) -> some View {
        let list = query.isEmpty ? entries : entries.filter { $0.title.localizedCaseInsensitiveContains(query) }
        if !list.isEmpty {
            Section(name) {
                ForEach(list.prefix(200)) { e in
                    Button { pick(e); dismiss() } label: {
                        HStack(spacing: 12) {
                            ArtworkView(entry: e, radius: 6).thumbnail().frame(width: 40, height: 40)
                            Text(e.title).foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }
}
