import SwiftUI
import UIKit

@main
struct MRSCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library: LibraryStore
    @State private var settings: AppSettings
    @State private var eq: EQModel
    @State private var player: PlayerModel
    @State private var router = Router()
    @State private var lyricsService: LyricsService
    @State private var mixService: MixService
    @State private var lab: AudioLab
    @State private var queueRules: QueueRules
    @State private var sources: SourceManager
    @State private var downloads: DownloadManager
    @State private var analysis: AnalysisService
    @State private var layout = LayoutStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var splash = SplashState.shared

    init() {
        let lib = LibraryStore()
        let settings = AppSettings()
        let eq = EQModel()
        let lab = AudioLab()
        let rules = QueueRules()
        let sources = SourceManager(library: lib)
        _library = State(initialValue: lib)
        _settings = State(initialValue: settings)
        _eq = State(initialValue: eq)
        _lab = State(initialValue: lab)
        _queueRules = State(initialValue: rules)
        _sources = State(initialValue: sources)
        StreamLoader.shared.sources = sources
        let player = PlayerModel(library: lib, settings: settings, eq: eq, lab: lab, rules: rules)
        player.sources = sources
        let service = LyricsService(library: lib, settings: settings)
        service.sources = sources
        let analysis = AnalysisService(library: lib)
        player.onTrackStarted = { [weak service, weak lib, weak analysis, weak player, weak settings] track in
            if let fresh = lib?.trackByID[track.id] {
                service?.autoDetect(for: fresh)
                if let lib, let settings { MotionArtwork.fillIn(for: fresh, library: lib, settings: settings) }
            }
            var ids = [track.id]
            if let next = player?.upcoming.first?.trackID { ids.append(next) }
            analysis?.prioritize(ids)
        }
        analysis.onAnalyzed = { [weak player] id in player?.trackAnalyzed(id) }
        lib.onFavoriteChanged = { [weak sources] t in sources?.favoriteChanged(t) }
        lib.onPlayed = { [weak sources] t in sources?.played(t) }
        _player = State(initialValue: player)
        _lyricsService = State(initialValue: service)
        _mixService = State(initialValue: MixService(library: lib))
        _downloads = State(initialValue: DownloadManager(library: lib, sources: sources))
        _analysis = State(initialValue: analysis)
        AppServices.shared.configure(library: lib, player: player, settings: settings, sources: sources)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .themeRoot()
                .environment(library)
                .environment(settings)
                .environment(eq)
                .environment(player)
                .environment(router)
                .environment(lyricsService)
                .environment(mixService)
                .environment(lab)
                .environment(queueRules)
                .environment(sources)
                .environment(downloads)
                .environment(analysis)
                .environment(layout)
                .overlay {
                    if splash.running { LaunchSplash { splash.running = false } }
                }
                .task {
                    if sources.autoSync { await sources.syncAll() }
                    try? await Task.sleep(for: .seconds(8))
                    analysis.analyzeWhenCharging()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { player.saveQueueNow() }
                }
        }
    }
}

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(SourceManager.self) private var sources
    @Environment(PlayerModel.self) private var player
    @Environment(LayoutStore.self) private var layout

    var body: some View {
        @Bindable var router = router
        Group {
            if layout.usesClassicBar {
                tabs.overlay { SearchLayer() }
            } else {
                tabs.tabViewBottomAccessory { MiniPlayer() }
            }
        }
        .fullScreenCover(isPresented: $router.showPlayer) {
            NowPlayingView()
        }
        .sheet(isPresented: $router.showSettings) { SettingsView().environment(\.inSettings, true) }
        .fullScreenCover(isPresented: $router.showFullLyrics) { FullScreenLyricsView() }
        .fullScreenCover(isPresented: $router.showOnboarding) { OnboardingView() }
        .sheet(isPresented: $router.showGoodbye) { GoodbyeView() }
        .onReceive(NotificationCenter.default.publisher(for: QuickActions.didRequest)) { _ in QuickActions.consume(router) }
        .sheet(isPresented: $router.showSongListImport) { SongListImportView() }
        .sheet(isPresented: $router.showAdd) { AddMusicSheet() }
        .fileImporter(isPresented: $router.showImporter,
                      allowedContentTypes: router.importKind?.contentTypes ?? [.audio],
                      allowsMultipleSelection: true) { result in
            guard let kind = router.importKind, case .success(let urls) = result else { return }
            Task { await library.handleImport(kind, urls: urls) }
        }
        .overlay(alignment: .top) { ImportOverlay() }
        .overlay(alignment: .top) { ThemePreviewBanner() }
        .animation(.smooth, value: library.importStatus != nil)
        .sheet(item: $router.moduleInstall) { ModuleInstallSheet(prompt: $0) }
        .onOpenURL { url in
            if let prompt = ModuleInstallPrompt.from(url) { router.moduleInstall = prompt; return }
            let ext = url.pathExtension.lowercased()
            if ext == "8spine" || ext == "js" {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let code = try? String(contentsOf: url, encoding: .utf8) { _ = try? ModuleStore.shared.install(code: code, sourceURL: nil) }
                return
            }
            if ext == "mrsctheme" || ext == "json", let t = ThemeStore.shared.importTheme(from: url) {
                ThemeStore.shared.preview(t)
            }
        }
        .onAppear {
            router.hasLibraryTab = layout.tabs.contains { $0.kind == .library }
            let d = UserDefaults.standard
            if !library.tracks.isEmpty || sources.hasSources { d.set(true, forKey: "onboarded") }
            if d.bool(forKey: "forceOnboarding") || !d.bool(forKey: "onboarded") {
                Task { await SplashState.shared.waitUntilDone(); router.showOnboarding = true }
            }
            QuickActions.consume(router)
        }
        .onChange(of: layout.tabs) { _, tabs in
            router.hasLibraryTab = tabs.contains { $0.kind == .library }
            if !tabs.contains(where: { $0.appTab == router.tab }) && router.tab != .search { router.tab = tabs.first?.appTab ?? .home }
        }
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            ForEach(layout.tabs) { item in
                Tab(item.title, systemImage: item.icon, value: item.appTab) { tabRoot(item) }
            }
            if !layout.usesClassicBar && layout.searchEnabled {
                Tab(value: AppTab.search, role: .search) {
                    NavigationStack {
                        SearchView()
                            .safeAreaInset(edge: .top) { SearchFieldBar() }
                            .navigationDestination(for: Route.self) { RouteView(route: $0) }
                    }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    @ViewBuilder private func tabRoot(_ item: TabItemConfig) -> some View {
        @Bindable var router = router
        switch item.kind {
        // The clearance goes on each page: a safe-area inset on the NavigationStack doesn't reach pushed pages.
        case .home:
            NavigationStack(path: pathBinding(item)) {
                HomeView().themedBackground().clearsMiniPlayer()
                    .navigationDestination(for: Route.self) { RouteView(route: $0).clearsMiniPlayer() }
            }
        case .library:
            NavigationStack(path: $router.libraryPath) {
                LibraryView().themedBackground().clearsMiniPlayer()
                    .navigationDestination(for: Route.self) { RouteView(route: $0).clearsMiniPlayer() }
            }
        default:
            NavigationStack(path: pathBinding(item)) {
                item.rootView.clearsMiniPlayer()
                    .navigationDestination(for: Route.self) { RouteView(route: $0).clearsMiniPlayer() }
            }
        }
    }

    private func pathBinding(_ item: TabItemConfig) -> Binding<[Route]> {
        let key = router.tabKey(item.appTab)
        return Binding(get: { router.paths[key] ?? [] }, set: { router.paths[key] = $0 })
    }
}

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .songs: SongsView().themedBackground()
        case .playlists: PlaylistsView().themedBackground()
        case .artists: ArtistsView().themedBackground()
        case .albums: AlbumsView().themedBackground()
        case .playlist(let id): CollectionDetailView(kind: .playlist, key: id.uuidString).themedBackground()
        case .artist(let name): CollectionDetailView(kind: .artist, key: name).themedBackground()
        case .album(let key): CollectionDetailView(kind: .album, key: key).themedBackground()
        case .equalizer: EqualizerView()
        case .metadata: MetadataListView().themedBackground()
        case .files: FilesView().themedBackground()
        case .studio: StudioView().themedBackground()
        case .audioLab: StudioView().themedBackground()
        case .trackMix: TrackMixView().themedBackground()
        case .downloads: DownloadsView().themedBackground()
        case .favorites: FavoritesView().themedBackground()
        case .radio: RadioView().themedBackground()
        case .recentlyPlayed: RecentlyPlayedView().themedBackground()
        case .sources: SourcesView().themedBackground()
        case .organize: OrganizeView().themedBackground()
        case .queueRules: QueueRulesView().themedBackground()
        }
    }
}

/// Search field for the standard tab-bar layout (the classic layout uses the floating search pill).
struct SearchFieldBar: View {
    @Environment(Router.self) private var router
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var router = router
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent)
            TextField("Songs, Artists, Albums — or “fast songs from 2016”", text: $router.searchText)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !router.searchText.isEmpty {
                Button { router.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .glassEffect(ThemeStore.shared.glass.interactive(), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .onAppear { if router.searchText.isEmpty { focused = true } }
    }
}

// MARK: - Home Screen quick actions

/// Long-press menu on the app icon. "Goodbye — see you soon" sits right above iOS's own "Remove App".
enum QuickActions {
    static let goodbye = "com.ecki.mrsc.goodbye"
    static let didRequest = Notification.Name("mrsc.quickAction")
    /// Set on a cold launch, before any view is listening.
    static var pending: String?

    static func handle(_ item: UIApplicationShortcutItem) {
        pending = item.type
        NotificationCenter.default.post(name: didRequest, object: nil)
    }

    static func consume(_ router: Router) {
        guard let type = pending else { return }
        pending = nil
        if type == goodbye { router.showGoodbye = true }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // CarPlay keeps its configuration from Info.plist; the phone window gets the quick-action delegate.
        guard session.role == .windowApplication else {
            return UISceneConfiguration(name: "CarPlay", sessionRole: session.role)
        }
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let item = options.shortcutItem { QuickActions.handle(item) }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        QuickActions.handle(shortcutItem)
        return true
    }
}
