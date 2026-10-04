import SwiftUI
import Observation
import UniformTypeIdentifiers

// MARK: - Model

extension UTType {
    nonisolated static let mrscTheme = UTType(exportedAs: "com.ecki.mrsc.theme", conformingTo: .json)
}

nonisolated struct AppTheme: Codable, Identifiable, Hashable, Sendable {
    enum Background: String, Codable, CaseIterable, Identifiable, Sendable {
        case system, solid, gradient, mesh
        var id: String { rawValue }
        var title: String { ["system": "System", "solid": "Solid Color", "gradient": "Gradient", "mesh": "Mesh"][rawValue] ?? rawValue }
    }
    enum FontStyle: String, Codable, CaseIterable, Identifiable, Sendable {
        case standard, rounded, serif, mono
        var id: String { rawValue }
        var title: String { ["standard": "Default", "rounded": "Rounded", "serif": "Serif", "mono": "Monospaced"][rawValue] ?? rawValue }
        var design: Font.Design {
            switch self {
            case .standard: .default
            case .rounded: .rounded
            case .serif: .serif
            case .mono: .monospaced
            }
        }
    }
    enum IconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
        case standard, filled, outline
        var id: String { rawValue }
        var title: String { ["standard": "Default", "filled": "Filled", "outline": "Outline"][rawValue] ?? rawValue }
    }
    enum Motion: String, Codable, CaseIterable, Identifiable, Sendable {
        case standard, snappy, relaxed, off
        var id: String { rawValue }
        var title: String { ["standard": "Standard", "snappy": "Snappy", "relaxed": "Relaxed", "off": "Off"][rawValue] ?? rawValue }
    }
    enum PlayerLayout: String, Codable, CaseIterable, Identifiable, Sendable {
        case classic, large, vinyl, minimal
        var id: String { rawValue }
        var title: String { ["classic": "Classic", "large": "Large Artwork", "vinyl": "Vinyl", "minimal": "Minimal"][rawValue] ?? rawValue }
    }
    enum QueueLayout: String, Codable, CaseIterable, Identifiable, Sendable {
        case comfortable, compact
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
    enum MiniPlayer: String, Codable, CaseIterable, Identifiable, Sendable {
        case capsule, compact, bar
        var id: String { rawValue }
        var title: String { ["capsule": "Capsule", "compact": "Compact", "bar": "Progress Bar"][rawValue] ?? rawValue }
    }
    /// Letter width for all system text: the fastest way to make MRSC feel like another app.
    enum TypeWidth: String, Codable, CaseIterable, Identifiable, Sendable {
        case standard, condensed, compressed, expanded
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var width: Font.Width? {
            switch self {
            case .standard: nil
            case .condensed: .condensed
            case .compressed: .compressed
            case .expanded: .expanded
            }
        }
    }
    /// A print surface laid over every screen.
    enum Texture: String, Codable, CaseIterable, Identifiable, Sendable {
        case none, grain, paper, halftone, scanlines
        var id: String { rawValue }
        var title: String { ["none": "None", "grain": "Film Grain", "paper": "Paper", "halftone": "Halftone", "scanlines": "Scanlines"][rawValue] ?? rawValue }
    }
    enum ArtShape: String, Codable, CaseIterable, Identifiable, Sendable {
        case rounded, sharp, circle, arch
        var id: String { rawValue }
        var title: String { ["rounded": "Rounded", "sharp": "Square", "circle": "Record", "arch": "Arch"][rawValue] ?? rawValue }
    }
    enum ArtFrame: String, Codable, CaseIterable, Identifiable, Sendable {
        case none, print, outline, glow
        var id: String { rawValue }
        var title: String { ["none": "None", "print": "White Border", "outline": "Ink Outline", "glow": "Glow"][rawValue] ?? rawValue }
    }
    enum NowPlayingBackground: String, Codable, CaseIterable, Identifiable, Sendable {
        case artworkTint, blurredArtwork, themeColors, black
        var id: String { rawValue }
        var title: String { ["artworkTint": "Artwork Color", "blurredArtwork": "Blurred Artwork", "themeColors": "Theme Colors", "black": "Black"][rawValue] ?? rawValue }
    }

    var id: String
    var name: String
    var author = "You"
    var inspiredBy: String?
    var summary: String?
    var accent = "#FF3B5C"
    /// 0 follows the app setting, 1 light, 2 dark.
    var scheme = 0
    var background: Background = .system
    var backgroundColors: [String] = ["#101014", "#26262E"]
    var blur = 0.5
    var transparency = 0.0
    var glass = 0.0
    var cornerScale = 1.0
    var font: FontStyle = .standard
    var icons: IconStyle = .standard
    var motion: Motion = .standard
    var playerLayout: PlayerLayout = .classic
    /// What the player screen shows and where (rows, buttons, menu).
    var player = PlayerConfig()
    var artworkScale = 1.0
    var queueLayout: QueueLayout = .comfortable
    var lyricsSize = 30.0
    var lyricsCentered = false
    var lyricsGlow = false
    var miniPlayer: MiniPlayer = .capsule
    var nowPlaying: NowPlayingBackground = .artworkTint
    var typeWidth: TypeWidth = .standard
    var allCaps = false
    /// Text color for the whole app; nil keeps the system's black/white.
    var ink: String?
    var texture: Texture = .none
    var artShape: ArtShape = .rounded
    var artFrame: ArtFrame = .none
    /// Tab bar this theme brings along (nil keeps the user's own). Applied when the theme is applied.
    var tabs: [TabItemConfig]?
    var searchTab: Bool?
    var builtIn = false

    init(id: String = UUID().uuidString, name: String) { self.id = id; self.name = name }

    // Lenient decoding: themes shared by others may come from older/newer versions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var t = AppTheme(id: (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString,
                         name: (try? c.decode(String.self, forKey: .name)) ?? "Imported Theme")
        func v<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? d }
        t.author = v(.author, t.author); t.inspiredBy = v(.inspiredBy, t.inspiredBy); t.summary = v(.summary, t.summary)
        t.accent = v(.accent, t.accent); t.scheme = v(.scheme, t.scheme); t.background = v(.background, t.background)
        t.backgroundColors = v(.backgroundColors, t.backgroundColors); t.blur = v(.blur, t.blur)
        t.transparency = v(.transparency, t.transparency); t.glass = v(.glass, t.glass); t.cornerScale = v(.cornerScale, t.cornerScale)
        t.font = v(.font, t.font); t.icons = v(.icons, t.icons); t.motion = v(.motion, t.motion)
        t.playerLayout = v(.playerLayout, t.playerLayout); t.player = v(.player, t.player); t.artworkScale = v(.artworkScale, t.artworkScale)
        t.queueLayout = v(.queueLayout, t.queueLayout); t.lyricsSize = v(.lyricsSize, t.lyricsSize)
        t.lyricsCentered = v(.lyricsCentered, t.lyricsCentered); t.lyricsGlow = v(.lyricsGlow, t.lyricsGlow)
        t.miniPlayer = v(.miniPlayer, t.miniPlayer); t.nowPlaying = v(.nowPlaying, t.nowPlaying)
        t.typeWidth = v(.typeWidth, t.typeWidth); t.allCaps = v(.allCaps, t.allCaps); t.ink = v(.ink, t.ink)
        t.texture = v(.texture, t.texture); t.artShape = v(.artShape, t.artShape); t.artFrame = v(.artFrame, t.artFrame)
        t.tabs = v(.tabs, t.tabs); t.searchTab = v(.searchTab, t.searchTab)
        t.builtIn = false
        self = t
    }

    var accentColor: Color { Color(hex: accent) }
    var colors: [Color] { (backgroundColors.isEmpty ? ["#101014"] : backgroundColors).map(Color.init(hex:)) }
    var colorScheme: ColorScheme? { scheme == 1 ? .light : scheme == 2 ? .dark : nil }
    var hasCustomBackground: Bool { background != .system }
    var inkColor: Color? { ink.map(Color.init(hex:)) }
}

nonisolated extension AppTheme: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mrscTheme) { theme in
            let safe = theme.name.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).mrsctheme")
            var copy = theme
            copy.builtIn = false
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(copy).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

// MARK: - Built-in themes

extension AppTheme {
    static let mrsc: AppTheme = {
        var t = AppTheme(id: "mrsc", name: "MRSC")
        t.author = "MRSC"; t.summary = "The original look."; t.builtIn = true
        t.tabs = [TabItemConfig(kind: .home), TabItemConfig(kind: .library)]
        t.searchTab = true
        return t
    }()

    /// MRSC's own look plus one theme per app people know. Each brings that app's look *and* its tab bar.
    static let builtIns: [AppTheme] = {
        var list = [mrsc]
        func tab(_ kind: TabKind, _ title: String, _ icon: String) -> TabItemConfig { TabItemConfig(kind: kind, title: title, icon: icon) }
        func make(_ id: String, _ name: String, _ build: (inout AppTheme) -> Void) {
            var t = AppTheme(id: id, name: name)
            t.author = "MRSC"; t.builtIn = true
            build(&t)
            list.append(t)
        }
        make("green-room", "Green Room") {
            // Spotify: devices bottom left, share and queue bottom right, heart next to the title.
            $0.player.bar = PlayerConfig.bar(.airplay, .spacer, .lyrics, .share, .queue)
            $0.player.playStyle = .glass; $0.player.spacing = .comfortable
            $0.inspiredBy = "Spotify"; $0.summary = "Near-black, bright green, big covers, Your Library."
            $0.accent = "#1DB954"; $0.scheme = 2; $0.background = .solid; $0.backgroundColors = ["#121212"]
            $0.cornerScale = 0.35; $0.playerLayout = .large; $0.nowPlaying = .artworkTint; $0.miniPlayer = .bar
            $0.lyricsSize = 28; $0.typeWidth = .standard
            // Home, Your Library, Search, and "+" to create, like Spotify.
            $0.tabs = [tab(.home, "Home", "house"), tab(.library, "Your Library", "books.vertical")]
            $0.searchTab = true
        }
        make("crimson", "Crimson") {
            // Apple Music: lyrics, AirPlay and queue spread across the bottom.
            $0.player.blocks = PlayerConfig.blocks(.artwork, .title, .scrubber, .controls, .bar)
            $0.player.bar = PlayerConfig.bar(.lyrics, .spacer, .airplay, .spacer, .queue)
            $0.player.showShuffleRepeat = false; $0.player.playStyle = .plain; $0.player.controlScale = 1.1
            $0.inspiredBy = "Apple Music"; $0.summary = "Soft glass, blurred covers, glowing lyrics."
            $0.accent = "#FA2D48"; $0.scheme = 0; $0.cornerScale = 1.1; $0.nowPlaying = .blurredArtwork; $0.blur = 0.75
            $0.lyricsSize = 32; $0.lyricsGlow = true; $0.glass = 0.1; $0.miniPlayer = .capsule
            $0.tabs = [tab(.home, "Home", "house.fill"), tab(.radio, "Radio", "dot.radiowaves.left.and.right"),
                       tab(.library, "Library", "music.note.square.stack.fill")]
            $0.searchTab = true
        }
        make("tube", "Tube") {
            // YouTube Music: centred title, Up Next / Lyrics tabs at the bottom.
            $0.player.titleAlignment = .center
            $0.player.bar = PlayerConfig.bar(.spacer, .modes, .spacer)
            $0.player.playStyle = .glass; $0.player.spacing = .roomy
            $0.inspiredBy = "YouTube Music"; $0.summary = "Pitch black, red highlights, centered lyrics."
            $0.accent = "#FF0033"; $0.scheme = 2; $0.background = .solid; $0.backgroundColors = ["#030303"]
            $0.cornerScale = 0.5; $0.playerLayout = .large; $0.nowPlaying = .blurredArtwork; $0.blur = 0.9
            $0.lyricsCentered = true; $0.lyricsSize = 27; $0.miniPlayer = .compact
            $0.tabs = [tab(.home, "Home", "house.fill"), tab(.radio, "Explore", "safari"), tab(.library, "Library", "square.stack")]
            $0.searchTab = true
        }
        make("cloud", "Cloud") {
            // SoundCloud: title above the cover, like, share, queue and more in one row.
            $0.player.blocks = PlayerConfig.blocks(.title, .artwork, .scrubber, .controls, .bar)
            $0.player.bar = PlayerConfig.bar(.favorite, .spacer, .lyrics, .spacer, .queue, .spacer, .more)
            $0.player.showStar = false; $0.player.showTitleMenu = false; $0.player.playStyle = .accent
            $0.inspiredBy = "SoundCloud"; $0.summary = "Dark, loud orange, everything at a glance."
            $0.accent = "#FF5500"; $0.scheme = 2; $0.background = .solid; $0.backgroundColors = ["#111111"]
            $0.cornerScale = 0.3; $0.playerLayout = .large; $0.nowPlaying = .blurredArtwork; $0.blur = 0.6
            $0.miniPlayer = .bar; $0.lyricsSize = 28
            $0.tabs = [tab(.home, "Home", "house.fill"), tab(.recentlyPlayed, "Feed", "rectangle.stack"),
                       tab(.library, "Library", "books.vertical")]
            $0.searchTab = true
        }
        make("tide", "Tide") {
            // TIDAL: centred, plain icons, nothing extra.
            $0.player.titleAlignment = .center
            $0.player.bar = PlayerConfig.bar(.airplay, .spacer, .lyrics, .queue)
            $0.player.playStyle = .plain; $0.player.showEQBadge = false; $0.player.spacing = .roomy
            $0.inspiredBy = "TIDAL"; $0.summary = "Black and white, wide headlines, nothing extra."
            $0.accent = "#F2F2F2"; $0.scheme = 2; $0.background = .solid; $0.backgroundColors = ["#000000"]
            $0.typeWidth = .expanded; $0.cornerScale = 0.15; $0.artShape = .sharp; $0.icons = .outline
            $0.playerLayout = .large; $0.nowPlaying = .black; $0.miniPlayer = .bar; $0.lyricsSize = 30
            $0.tabs = [tab(.home, "Home", "house"), tab(.radio, "Explore", "safari"), tab(.library, "My Collection", "heart")]
            $0.searchTab = true
        }
        make("pulse", "Pulse") {
            // Deezer: round accent play button, favourite and timer either side of the views.
            $0.player.bar = PlayerConfig.bar(.favorite, .modes, .sleep)
            $0.player.showStar = false; $0.player.playStyle = .accent; $0.player.controlScale = 1.05
            $0.inspiredBy = "Deezer"; $0.summary = "Deep purple night, rounded letters, Flow first."
            $0.accent = "#A238FF"; $0.scheme = 2; $0.background = .gradient; $0.backgroundColors = ["#0F0D13", "#1D1430"]
            $0.font = .rounded; $0.cornerScale = 1.0; $0.nowPlaying = .artworkTint; $0.miniPlayer = .capsule
            $0.tabs = [tab(.home, "Home", "house.fill"), tab(.radio, "Explore", "safari"), tab(.library, "Favorites", "heart.fill")]
            $0.searchTab = true
        }
        return list
    }()
}

// MARK: - Store

@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private(set) var custom: [AppTheme] = [] { didSet { _selected = nil; save() } }
    var selectedID: String { didSet { _selected = nil; UserDefaults.standard.set(selectedID, forKey: "themeID") } }
    /// While set, the whole app renders with this theme (live preview before applying).
    var previewing: AppTheme?
    var favorites: Set<String> { didSet { UserDefaults.standard.set(Array(favorites), forKey: "themeFavorites") } }
    var ratings: [String: Int] { didSet { UserDefaults.standard.set(ratings, forKey: "themeRatings") } }

    private static var fileURL: URL { Paths.support.appendingPathComponent("themes.json") }

    private init() {
        let d = UserDefaults.standard
        selectedID = d.string(forKey: "themeID") ?? AppTheme.mrsc.id
        favorites = Set(d.stringArray(forKey: "themeFavorites") ?? [])
        ratings = (d.dictionary(forKey: "themeRatings") as? [String: Int]) ?? [:]
        if let data = try? Data(contentsOf: Self.fileURL), let list = try? JSONDecoder().decode([AppTheme].self, from: data) { custom = list }
    }

    var all: [AppTheme] { AppTheme.builtIns + custom }
    /// Every cover, row and button asks for the theme, so the lookup is kept until the selection or the themes change.
    @ObservationIgnored private var _selected: AppTheme?
    var selected: AppTheme {
        // Read both so views keep following theme changes when the cached value is used.
        _ = selectedID; _ = custom
        if let hit = _selected { return hit }
        let t = all.first { $0.id == selectedID } ?? .mrsc
        _selected = t
        return t
    }
    var current: AppTheme { previewing ?? selected }

    /// `edited`: saving a change to the current theme (or to the copy a built-in one becomes). Only picking another
    /// theme brings its tab bar; an edit must never replace the tabs you have.
    func apply(_ t: AppTheme, edited: Bool = false) {
        if !all.contains(where: { $0.id == t.id }) { save(t) }
        let switching = !edited && t.id != selectedID
        withAnimation(.smooth(duration: 0.5)) {
            selectedID = t.id; previewing = nil
            if switching { LayoutStore.shared.adoptTabs(of: t) }
        }
    }

    func preview(_ t: AppTheme?) { withAnimation(.smooth(duration: 0.4)) { previewing = t } }

    func save(_ t: AppTheme) {
        var t = t
        t.builtIn = false
        if let i = custom.firstIndex(where: { $0.id == t.id }) { custom[i] = t } else { custom.append(t) }
    }

    func delete(_ t: AppTheme) {
        custom.removeAll { $0.id == t.id }
        if selectedID == t.id { selectedID = AppTheme.mrsc.id }
    }

    func duplicate(_ t: AppTheme) -> AppTheme {
        var copy = t
        copy.id = UUID().uuidString
        copy.name = t.name + " Copy"
        copy.author = "You"
        copy.builtIn = false
        return copy
    }

    func toggleFavorite(_ t: AppTheme) { if favorites.contains(t.id) { favorites.remove(t.id) } else { favorites.insert(t.id) } }

    @discardableResult
    func importTheme(data: Data) -> AppTheme? {
        guard var t = try? JSONDecoder().decode(AppTheme.self, from: data) else { return nil }
        if AppTheme.builtIns.contains(where: { $0.id == t.id }) { t.id = UUID().uuidString }
        save(t)
        return t
    }

    func importTheme(from url: URL) -> AppTheme? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return importTheme(data: data)
    }

    // Glass used by the floating controls.
    var glass: Glass {
        let t = current
        let base: Glass = t.transparency > 0.6 ? .clear : .regular
        return t.glass > 0.01 ? base.tint(t.accentColor.opacity(t.glass * 0.35)) : base
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) { try? data.write(to: Self.fileURL, options: .atomic) }
    }
}

// MARK: - Applying a theme

struct ThemeRoot: ViewModifier {
    @Environment(AppSettings.self) private var settings
    func body(content: Content) -> some View {
        let t = ThemeStore.shared.current
        let scheme = t.colorScheme ?? settings.colorScheme
        content
            .preferredColorScheme(scheme)
            // SwiftUI keeps a forced dark/light window after the preference goes back to nil ("System");
            // setting the window style directly makes the switch back work, e.g. from a dark theme to MRSC.
            .onChange(of: scheme, initial: true) { _, s in
                let style: UIUserInterfaceStyle = s == .dark ? .dark : s == .light ? .light : .unspecified
                // Open sheets keep the style they were presented with, so walk them too.
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    for window in scene.windows {
                        window.overrideUserInterfaceStyle = style
                        var vc = window.rootViewController?.presentedViewController
                        while let presented = vc {
                            presented.overrideUserInterfaceStyle = style
                            vc = presented.presentedViewController
                        }
                    }
                }
            }
            .tint(t.accentColor)
            .fontDesign(t.font.design)
            .fontWidth(t.typeWidth.width)
            .textCase(t.allCaps ? .uppercase : nil)
            .foregroundStyle(t.inkColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
            .overlay { ThemeTexture(kind: t.texture).ignoresSafeArea() }
            .modifier(IconStyleModifier(style: t.icons))
            .transaction { tr in
                switch t.motion {
                case .standard: break
                case .snappy: tr.animation = tr.animation?.speed(1.5)
                case .relaxed: tr.animation = tr.animation?.speed(0.7)
                case .off: tr.animation = nil
                }
            }
    }
}

private struct IconStyleModifier: ViewModifier {
    let style: AppTheme.IconStyle
    @Environment(\.symbolVariants) private var inherited
    // One structure for every style: switching between `content` and `content.environment(…)` would give the
    // whole app a new identity on a theme change and throw away its state (onboarding, navigation, sheets).
    // "Filled" is kept for older theme files but behaves like the default: a global fill
    // would turn state icons such as the favourite star into their "on" look.
    func body(content: Content) -> some View {
        content.environment(\.symbolVariants, style == .outline ? .none : inherited)
    }
}

struct ThemeBackgroundView: View {
    var theme: AppTheme { ThemeStore.shared.current }
    var body: some View {
        let t = theme
        Group {
            switch t.background {
            case .system: Color(.systemBackground)
            case .solid: t.colors[0]
            case .gradient: LinearGradient(colors: t.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            case .mesh:
                TimelineView(.animation(minimumInterval: 1 / 20, paused: t.motion == .off)) { ctx in
                    let s = Float(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) / 60 * 2 * .pi)
                    let c = t.colors + t.colors
                    MeshGradient(width: 3, height: 3, points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5 + 0.2 * sin(s), 0.5 + 0.15 * cos(s * 1.3)], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ], colors: [c[0], c[1], c[0], c[2 % c.count], c[1], c[2 % c.count], c[0], c[2 % c.count], c[1]])
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct ThemedBackground: ViewModifier {
    // Same structure with or without a custom background, so switching themes keeps the screen's state.
    func body(content: Content) -> some View {
        let custom = ThemeStore.shared.current.hasCustomBackground
        content
            .scrollContentBackground(custom ? .hidden : .automatic)
            .background { if custom { ThemeBackgroundView() } }
    }
}

extension View {
    func themedBackground() -> some View { modifier(ThemedBackground()) }
    func themeRoot() -> some View { modifier(ThemeRoot()) }
}

// MARK: - Gallery

struct ThemesView: View {
    enum Filter: String, CaseIterable, Identifiable { case all = "All", favorites = "Favorites", mine = "Mine"; var id: String { rawValue } }

    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    private var store: ThemeStore { ThemeStore.shared }
    @State private var filter: Filter = .all
    @State private var detail: AppTheme?
    @State private var editing: AppTheme?
    @State private var importing = false
    @State private var linkPrompt = false
    @State private var link = ""
    @State private var message: String?

    private var shown: [AppTheme] {
        switch filter {
        case .all: store.all
        case .favorites: store.all.filter { store.favorites.contains($0.id) }
        case .mine: store.custom
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Show", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                    ForEach(shown) { t in
                        Button { detail = t } label: { ThemeCard(theme: t, selected: store.selectedID == t.id, favorite: store.favorites.contains(t.id)) }
                            .buttonStyle(PressScale())
                            .contextMenu {
                                Button { store.apply(t) } label: { Label("Apply", systemImage: "checkmark") }
                                Button { previewInApp(t) } label: { Label("Preview", systemImage: "eye") }
                                Button { store.toggleFavorite(t) } label: { Label(store.favorites.contains(t.id) ? "Unfavorite" : "Favorite", systemImage: "heart") }
                                Button { editing = store.duplicate(t) } label: { Label("Duplicate & Edit", systemImage: "plus.square.on.square") }
                                ShareLink(item: t, preview: SharePreview(t.name)) { Label("Share", systemImage: "square.and.arrow.up") }
                                if !t.builtIn {
                                    Button { editing = t } label: { Label("Edit", systemImage: "pencil") }
                                    Button(role: .destructive) { store.delete(t) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                    }
                }
                if shown.isEmpty {
                    ContentUnavailableView(filter == .favorites ? "No Favorite Themes" : "No Themes Yet", systemImage: "paintpalette",
                                           description: Text(filter == .favorites ? "Tap the heart on a theme you like." : "Create one or import a theme someone shared."))
                }
                Text("Themes are small .mrsctheme files. Share yours with AirDrop, Messages or a link; open a shared file or link here to add it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("Themes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = store.duplicate(store.selected) } label: { Label("Create Theme", systemImage: "paintbrush") }
                    Button { var t = AppTheme.surprise(); t.author = "You"; editing = t } label: { Label("Surprise Me", systemImage: "dice") }
                    Button { importing = true } label: { Label("Import File…", systemImage: "square.and.arrow.down") }
                    Button { link = ""; linkPrompt = true } label: { Label("Import from Link…", systemImage: "link") }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $detail) { t in
            ThemeDetail(theme: t, edit: { t in
                // Wait for the detail sheet to finish closing before the editor sheet opens.
                Task { try? await Task.sleep(for: .milliseconds(450)); editing = t }
            }, close: { detail = nil }, preview: { detail = nil; previewInApp($0) })
        }
        .sheet(item: $editing) { t in ThemeEditor(theme: t) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.mrscTheme, .json]) { result in
            guard case .success(let url) = result else { return }
            message = store.importTheme(from: url).map { "Added “\($0.name)”." } ?? "That file isn't a theme."
        }
        .alert("Import from Link", isPresented: $linkPrompt) {
            TextField("https://…", text: $link).textInputAutocapitalization(.never).keyboardType(.URL)
            Button("Import") { Task { await importLink() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Paste a link to a .mrsctheme or JSON theme file, for example from a community thread or gist.") }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} }
    }

    /// The preview has to be seen on the real app, so the settings sheet closes; the banner at the top applies or cancels.
    private func previewInApp(_ t: AppTheme) {
        store.preview(t)
        router.showSettings = false
    }

    private func importLink() async {
        guard var url = URL(string: link.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true else {
            message = "That isn't a web link."; return
        }
        // GitHub "blob" pages → raw file.
        if url.host() == "github.com", url.path().contains("/blob/") {
            url = URL(string: url.absoluteString.replacingOccurrences(of: "github.com", with: "raw.githubusercontent.com").replacingOccurrences(of: "/blob/", with: "/")) ?? url
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            message = store.importTheme(data: data).map { "Added “\($0.name)”." } ?? "No theme found at that link."
        } catch {
            message = error.localizedDescription
        }
    }
}

struct ThemeCard: View {
    let theme: AppTheme
    var selected = false
    var favorite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemeMock(theme: theme)
                .aspectRatio(0.78, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        if favorite { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, theme.accentColor) }
                    }
                    .font(.system(size: 16, weight: .bold))
                    .padding(8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(selected ? theme.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 1)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(theme.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                Text(theme.inspiredBy.map { "Inspired by \($0)" } ?? theme.summary ?? "by \(theme.author)")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// A tiny drawing of the app in a theme: background, cover, lyric lines, accent controls.
struct ThemeMock: View {
    let theme: AppTheme
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // The mock shows the player, whose backgrounds are dark except light theme colors.
            let fg: Color = theme.nowPlaying == .themeColors && theme.scheme == 1 ? .black : .white
            let ink = theme.nowPlaying == .themeColors ? (theme.inkColor ?? fg) : fg
            ZStack {
                background
                ThemeTexture(kind: theme.texture).environment(\.colorScheme, theme.scheme == 1 && theme.nowPlaying == .themeColors ? .light : .dark)
                VStack(alignment: theme.lyricsCentered ? .center : .leading, spacing: w * 0.05) {
                    Text(theme.name)
                        .font(.system(size: w * 0.1, weight: .heavy))
                        .fontWidth(theme.typeWidth.width)
                        .textCase(theme.allCaps ? .uppercase : nil)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    cover
                        .frame(width: theme.playerLayout == .large ? w * 0.84 : theme.playerLayout == .minimal ? w * 0.35 : w * 0.62)
                        .frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.45)).frame(width: w * 0.32, height: w * 0.04)
                    Capsule().fill(ink.opacity(0.25)).frame(height: 3)
                        .overlay(alignment: .leading) { Capsule().fill(theme.accentColor).frame(width: w * 0.35, height: 3) }
                    HStack(spacing: w * 0.07) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "play.fill").font(.system(size: w * 0.11))
                            .foregroundStyle(theme.accentColor)
                        Image(systemName: "forward.fill")
                    }
                    .font(.system(size: w * 0.08))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
                    if let tabs = theme.tabs {
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                                VStack(spacing: 2) {
                                    Image(systemName: tab.icon).font(.system(size: w * 0.07))
                                    Text(tab.title).font(.system(size: w * 0.045, weight: .medium)).lineLimit(1).minimumScaleFactor(0.5)
                                }
                                .foregroundStyle(i == 0 ? theme.accentColor : ink.opacity(0.6))
                                .frame(maxWidth: .infinity)
                            }
                            if theme.searchTab ?? true {
                                Image(systemName: "magnifyingglass").font(.system(size: w * 0.07))
                                    .foregroundStyle(ink.opacity(0.6))
                                    .frame(width: w * 0.16)
                            }
                        }
                        .padding(.vertical, w * 0.025)
                        .background(Capsule().fill(.ultraThinMaterial))
                    }
                }
                .padding(w * 0.09)
            }
            .fontDesign(theme.font.design)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private var background: some View {
        switch theme.nowPlaying {
        case .artworkTint: LinearGradient(colors: [theme.accentColor.opacity(0.85), .black], startPoint: .top, endPoint: .bottom)
        case .blurredArtwork: ZStack { GeneratedCover(spec: CoverKit.auto(theme.name)).blur(radius: 14); Color.black.opacity(0.35) }
        case .themeColors: LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .black: Color.black
        }
    }

    private var cover: some View {
        let shape = theme.playerLayout == .vinyl ? AnyShape(Circle()) : theme.artShape.shape(radius: 10 * theme.cornerScale)
        return GeneratedCover(spec: CoverKit.auto(theme.name + "cover"))
            .aspectRatio(1, contentMode: .fit)
            .clipShape(shape)
            .overlay { ArtFrameOverlay(frame: theme.artFrame, shape: shape, accent: theme.accentColor, ink: theme.inkColor) }
            .overlay { if theme.playerLayout == .vinyl { Circle().fill(.black).frame(width: 10, height: 10) } }
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

struct ThemeDetail: View {
    @Environment(\.dismiss) private var dismiss
    let theme: AppTheme
    var edit: (AppTheme) -> Void
    var close: () -> Void
    var preview: (AppTheme) -> Void
    private var store: ThemeStore { ThemeStore.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 14) {
                        ThemeMock(theme: theme).frame(width: 200, height: 270).shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                        PlayerPreview(theme: theme).frame(height: 270)
                    }
                    VStack(spacing: 4) {
                        Text(theme.name).font(.title2.bold())
                        if let i = theme.inspiredBy { Text("Inspired by \(i)").foregroundStyle(.secondary) }
                        if let s = theme.summary { Text(s).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        Text("by \(theme.author)").font(.caption).foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { n in
                            Button { store.ratings[theme.id] = store.ratings[theme.id] == n ? nil : n } label: {
                                Image(systemName: (store.ratings[theme.id] ?? 0) >= n ? "star.fill" : "star")
                                    .font(.title3).foregroundStyle(.yellow)
                            }
                            .buttonStyle(.plain)
                        }
                        Button { store.toggleFavorite(theme) } label: {
                            Image(systemName: store.favorites.contains(theme.id) ? "heart.fill" : "heart").font(.title3).foregroundStyle(.pink)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 10)
                    }
                    .sensoryFeedback(.selection, trigger: store.ratings[theme.id])

                    VStack(spacing: 10) {
                        Button { store.apply(theme); close() } label: { Text("Apply Theme").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.glassProminent).tint(theme.accentColor)
                        Button { preview(theme) } label: { Text("Preview in App").frame(maxWidth: .infinity, minHeight: 44) }
                            .buttonStyle(.glass)
                        HStack(spacing: 10) {
                            Button { close(); edit(theme.builtIn ? store.duplicate(theme) : theme) } label: { Label(theme.builtIn ? "Duplicate" : "Edit", systemImage: theme.builtIn ? "plus.square.on.square" : "pencil").frame(maxWidth: .infinity, minHeight: 40) }
                            ShareLink(item: theme, preview: SharePreview(theme.name)) { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 40) }
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 20)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

/// Floating banner while a theme is being previewed.
struct ThemePreviewBanner: View {
    var body: some View {
        let store = ThemeStore.shared
        if let t = store.previewing {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill").foregroundStyle(t.accentColor)
                Text("Previewing \(t.name)").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button("Cancel") { store.preview(nil) }.buttonStyle(.glass)
                Button("Apply") { store.apply(t) }.buttonStyle(.glassProminent).tint(t.accentColor)
            }
            .font(.system(size: 14))
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Editor

struct ThemeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @State var theme: AppTheme

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ThemeMock(theme: theme).frame(width: 170, height: 220).frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section {
                    Button {
                        let fresh = AppTheme.surprise()
                        withAnimation(.smooth(duration: 0.4)) {
                            let keep = (theme.id, theme.author)
                            theme = fresh
                            theme.id = keep.0; theme.author = keep.1
                        }
                    } label: { Label("Surprise Me", systemImage: "dice") }
                }
                Section("Name") {
                    TextField("Name", text: $theme.name)
                    TextField("Author", text: $theme.author)
                    TextField("Inspired by (optional)", text: Binding(get: { theme.inspiredBy ?? "" }, set: { theme.inspiredBy = $0.isEmpty ? nil : $0 }))
                }
                Section("Colors") {
                    ColorPicker("Accent", selection: hex(\.accent), supportsOpacity: false)
                    Picker("Appearance", selection: $theme.scheme) {
                        Text("Follow Setting").tag(0); Text("Light").tag(1); Text("Dark").tag(2)
                    }
                    Picker("Background", selection: $theme.background) { ForEach(AppTheme.Background.allCases) { Text($0.title).tag($0) } }
                    if theme.background != .system {
                        ForEach(0..<(theme.background == .solid ? 1 : 3), id: \.self) { i in
                            ColorPicker(theme.background == .solid ? "Color" : "Color \(i + 1)", selection: bgColor(i), supportsOpacity: false)
                        }
                    }
                }
                Section {
                    Picker("Letter Width", selection: $theme.typeWidth) { ForEach(AppTheme.TypeWidth.allCases) { Text($0.title).tag($0) } }
                    Toggle("All Caps", isOn: $theme.allCaps)
                    Toggle("Custom Text Color", isOn: Binding(get: { theme.ink != nil }, set: { theme.ink = $0 ? (theme.ink ?? (theme.scheme == 2 ? "#F2F2F2" : "#141414")) : nil }))
                    if theme.ink != nil {
                        ColorPicker("Text Color", selection: Binding(get: { theme.inkColor ?? .primary }, set: { theme.ink = $0.hexString }), supportsOpacity: false)
                    }
                    Picker("Surface", selection: $theme.texture) { ForEach(AppTheme.Texture.allCases) { Text($0.title).tag($0) } }
                    Picker("Cover Shape", selection: $theme.artShape) { ForEach(AppTheme.ArtShape.allCases) { Text($0.title).tag($0) } }
                    Picker("Cover Frame", selection: $theme.artFrame) { ForEach(AppTheme.ArtFrame.allCases) { Text($0.title).tag($0) } }
                } header: { Text("Personality") } footer: {
                    Text("These change every screen: letter width and case, text color, a print surface over the app, and how covers are cut and framed.")
                }
                Section("Glass & Shape") {
                    slider("Blur", $theme.blur, 0...1)
                    slider("Transparency", $theme.transparency, 0...1)
                    slider("Glass Intensity", $theme.glass, 0...1)
                    slider("Corner Radius", $theme.cornerScale, 0...1.8)
                }
                Section("Type & Motion") {
                    Picker("Font", selection: $theme.font) { ForEach(AppTheme.FontStyle.allCases) { Text($0.title).tag($0) } }
                    Picker("Icons", selection: $theme.icons) { ForEach(AppTheme.IconStyle.allCases.filter { $0 != .filled }) { Text($0.title).tag($0) } }
                    Picker("Animations", selection: $theme.motion) { ForEach(AppTheme.Motion.allCases) { Text($0.title).tag($0) } }
                }
                Section("Player") {
                    NavigationLink { PlayerLayoutEditor(theme: $theme) } label: {
                        Label("Music Player Layout", systemImage: "play.rectangle")
                    }
                    Picker("Queue", selection: $theme.queueLayout) { ForEach(AppTheme.QueueLayout.allCases) { Text($0.title).tag($0) } }
                    Picker("Mini Player", selection: $theme.miniPlayer) { ForEach(AppTheme.MiniPlayer.allCases) { Text($0.title).tag($0) } }
                }
                Section("Lyrics") {
                    slider("Text Size", $theme.lyricsSize, 20...44)
                    Toggle("Centered", isOn: $theme.lyricsCentered)
                    Toggle("Glow on Current Line", isOn: $theme.lyricsGlow)
                }
                Section {
                    Button("Preview in App") {
                        // Not saved yet: "Apply" in the preview banner keeps it, "Cancel" throws it away.
                        ThemeStore.shared.preview(theme)
                        dismiss()
                        router.showSettings = false
                    }
                }
            }
            .navigationTitle("Edit Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { ThemeStore.shared.save(theme); ThemeStore.shared.apply(theme, edited: true); dismiss() }
                }
            }
        }
    }

    private func hex(_ path: WritableKeyPath<AppTheme, String>) -> Binding<Color> {
        Binding(get: { Color(hex: theme[keyPath: path]) }, set: { theme[keyPath: path] = $0.hexString })
    }

    private func bgColor(_ i: Int) -> Binding<Color> {
        Binding(get: { theme.backgroundColors.indices.contains(i) ? Color(hex: theme.backgroundColors[i]) : .black },
                set: { c in
                    while theme.backgroundColors.count <= i { theme.backgroundColors.append(theme.backgroundColors.last ?? "#101014") }
                    theme.backgroundColors[i] = c.hexString
                })
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range)
        }
    }
}
