import SwiftUI
import AVFoundation
import ShazamKit

// MARK: - Categories

/// A genre tile in Search. Library songs join a category when one of their genre tags starts a word with one of `keys`
/// ("Indie Rock" is Rock and Alternative), so a song can sit in more than one, like in Apple Music.
struct BrowseCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let keys: [String]
    let colors: [Color]
    /// What extensions are asked for when the library has no artists to start from.
    var online: String { title }

    func contains(_ genre: String) -> Bool {
        let g = " " + SmartSearch.norm(genre).replacingOccurrences(of: #"[^a-z0-9&]+"#, with: " ", options: .regularExpression)
        return keys.contains { g.contains(" " + $0) }
    }

    private static func tile(_ id: String, _ title: String, _ keys: [String], _ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> BrowseCategory {
        BrowseCategory(id: id, title: title, keys: keys,
                       colors: [Color(hue: a.0, saturation: a.1, brightness: a.2), Color(hue: b.0, saturation: b.1, brightness: b.2)])
    }

    /// Apple Music's order. Keys are normalised (lowercase, no accents, punctuation as spaces).
    static let standard: [BrowseCategory] = [
        tile("pop", "Pop", ["pop", "synthpop", "k pop", "j pop", "europop"], (0.95, 0.75, 0.95), (0.88, 0.85, 0.6)),
        tile("hiphop", "Hip-Hop/Rap", ["hip hop", "hiphop", "rap", "trap", "grime", "drill", "deutschrap"], (0.08, 0.85, 0.9), (0.0, 0.85, 0.55)),
        tile("rock", "Rock", ["rock", "grunge"], (0.0, 0.8, 0.8), (0.97, 0.9, 0.4)),
        tile("dance", "Dance", ["dance", "edm", "house", "disco", "eurodance"], (0.78, 0.65, 0.95), (0.7, 0.85, 0.55)),
        tile("rnb", "R&B/Soul", ["r&b", "r & b", "rnb", "rhythm and blues", "soul", "funk", "neo soul"], (0.6, 0.6, 0.85), (0.72, 0.8, 0.45)),
        tile("alternative", "Alternative", ["alternative", "alt", "indie", "emo", "shoegaze", "post punk"], (0.47, 0.7, 0.75), (0.55, 0.85, 0.45)),
        tile("electronic", "Electronic", ["electro", "techno", "trance", "drum and bass", "drum & bass", "dnb", "dubstep", "ambient", "idm", "synthwave", "downtempo"], (0.53, 0.85, 0.95), (0.62, 0.9, 0.55)),
        tile("folk", "Folk", ["folk", "acoustic", "americana", "singer songwriter", "liedermacher"], (0.11, 0.6, 0.8), (0.07, 0.7, 0.45)),
        tile("metal", "Metal", ["metal", "hardcore", "deathcore"], (0.0, 0.0, 0.42), (0.0, 0.0, 0.12)),
        tile("jazz", "Jazz", ["jazz", "swing", "bebop", "bossa nova"], (0.13, 0.8, 0.85), (0.6, 0.6, 0.35)),
        tile("classical", "Classical", ["classical", "klassik", "orchestral", "baroque", "opera", "symphon"], (0.12, 0.35, 0.8), (0.1, 0.5, 0.4)),
        tile("country", "Country", ["country", "bluegrass"], (0.08, 0.65, 0.85), (0.04, 0.75, 0.5)),
        tile("latin", "Latin", ["latin", "reggaeton", "salsa", "bachata", "cumbia", "urbano"], (0.02, 0.75, 0.95), (0.9, 0.8, 0.6)),
        tile("reggae", "Reggae", ["reggae", "dancehall", "ska"], (0.3, 0.75, 0.7), (0.15, 0.85, 0.45)),
        tile("blues", "Blues", ["blues"], (0.6, 0.8, 0.7), (0.62, 0.9, 0.35)),
        tile("punk", "Punk", ["punk"], (0.92, 0.85, 0.85), (0.0, 0.0, 0.15)),
        tile("soundtrack", "Soundtrack", ["soundtrack", "score", "film", "ost", "musical", "video game"], (0.67, 0.4, 0.55), (0.67, 0.5, 0.25)),
        tile("schlager", "Schlager", ["schlager", "volksmusik"], (0.9, 0.55, 0.95), (0.95, 0.75, 0.6)),
    ]

    /// A library genre that fits none of the standard tiles, shown as its own tile.
    static func custom(_ genre: String) -> BrowseCategory {
        let c = placeholderColors(seed: genre)
        return BrowseCategory(id: "tag:" + SmartSearch.norm(genre), title: genre, keys: [], colors: [c.0, c.1])
    }
}

/// The tiles worth showing: categories with songs in the library first (most songs first), then, when an extension
/// can search, the remaining standard ones. Leftover genre tags with enough songs get their own tile.
@MainActor
enum BrowseCatalog {
    static func songs(_ category: BrowseCategory, in library: LibraryStore) -> [Track] {
        library.memo("browse.songs." + category.id) {
            if category.keys.isEmpty {
                let tag = SmartSearch.norm(category.title)
                return library.tracks.filter { $0.genre.map(SmartSearch.norm) == tag }
            }
            var verdict: [String: Bool] = [:]
            return library.tracks.filter { t in
                guard let g = t.genre, !g.isEmpty else { return false }
                if let v = verdict[g] { return v }
                let v = category.contains(g)
                verdict[g] = v
                return v
            }
        }
    }

    static func categories(library: LibraryStore, online: Bool) -> [BrowseCategory] {
        let local: [(BrowseCategory, Int)] = library.memo("browse.local") {
            let genres = Dictionary(grouping: library.tracks.compactMap(\.genre).filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
            var counts: [String: Int] = [:]
            var leftovers: [String: Int] = [:]
            for (g, n) in genres {
                let hits = BrowseCategory.standard.filter { $0.contains(g) }
                if hits.isEmpty { leftovers[SmartSearch.norm(g), default: 0] += n }
                for c in hits { counts[c.id, default: 0] += n }
            }
            let names = Dictionary(genres.keys.map { (SmartSearch.norm($0), $0) }, uniquingKeysWith: { a, _ in a })
            var out = BrowseCategory.standard.compactMap { c in counts[c.id].map { (c, $0) } }
            out += leftovers.filter { $0.value >= 8 }.compactMap { k, n in names[k].map { (BrowseCategory.custom($0), n) } }
            return out.sorted { $0.1 > $1.1 }
        }
        var list = local.map(\.0)
        if online {
            let have = Set(list.map(\.id))
            list += BrowseCategory.standard.filter { !have.contains($0.id) }
        }
        return list
    }

    /// A song to put on the tile: the most played one, else the newest.
    static func cover(_ category: BrowseCategory, in library: LibraryStore) -> Track? {
        let list = songs(category, in: library)
        return list.max { ($0.playCount ?? 0, $0.addedAt) < ($1.playCount ?? 0, $1.addedAt) }
    }
}

/// "Browse Categories" in Search before anything is typed.
/// Tiles are buttons, not NavigationLinks: the whole grid is one List row, and a row with several links fires all of them,
/// pushing every category at once. SearchView pushes `selection` instead.
struct BrowseCategoriesSection: View {
    @Environment(LibraryStore.self) private var library
    let online: Bool
    @Binding var selection: BrowseCategory?
    @State private var showAll = false

    var body: some View {
        let all = BrowseCatalog.categories(library: library, online: online)
        if !all.isEmpty {
            let shown = showAll ? all : Array(all.prefix(8))
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(shown) { c in
                        Button {
                            selection = c
                        } label: {
                            BrowseTile(category: c, cover: BrowseCatalog.cover(c, in: library))
                        }
                        .buttonStyle(PressScale())
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                HStack {
                    Text("Browse Categories")
                    Spacer()
                    if all.count > 8 {
                        Button(showAll ? "Show Less" : "Show All") { withAnimation(.snappy) { showAll.toggle() } }
                            .font(.app(size: 13, weight: .semibold))
                    }
                }
                .textCase(nil)
            }
        }
    }
}

/// Apple Music style: a full-bleed photo with the name bottom left. Standard categories use a bundled photo
/// (Assets.xcassets/Browse, Unsplash License, credits in README); a library genre without one uses its cover.
private struct BrowseTile: View {
    let category: BrowseCategory
    let cover: Track?

    private var image: UIImage? {
        UIImage(named: "browse-" + category.id) ?? cover.flatMap { ArtworkCache.image(for: $0, maxPixel: 480) }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14 * ThemeStore.shared.current.cornerScale, style: .continuous)
        LinearGradient(colors: category.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .overlay {
                // Keeps the white title readable on bright photos.
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                Text(category.title)
                    .font(.app(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .lineLimit(2)
                    .padding(12)
            }
            .frame(height: 104)
            .clipShape(shape)
            .contentShape(shape)
    }
}

/// One category: its songs and albums from the library, then what extensions find for it.
struct BrowseCategoryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(AppSettings.self) private var settings
    let category: BrowseCategory
    @State private var online: [(InstalledModule, [ModuleTrack])] = []
    @State private var loading = false

    private var canDiscover: Bool { ModuleStore.shared.canDiscover(offlineMode: settings.offlineMode) }

    var body: some View {
        let songs = BrowseCatalog.songs(category, in: library)
        let ids = Set(songs.map(\.id))
        let albums = library.albumEntries.filter { $0.tracks.contains { ids.contains($0.id) } }
        List {
            if !songs.isEmpty {
                PlayShuffleBar(tracks: songs, title: category.title)
                    .listRowSeparator(.hidden)
            }
            if !albums.isEmpty {
                Section("Albums") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(albums.prefix(30)) { e in
                                NavigationLink(value: e.route) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ArtworkView(entry: e).thumbnail(320).frame(width: 140, height: 140)
                                        Text(e.title).font(.app(size: 14, weight: .medium)).lineLimit(1).foregroundStyle(.primary)
                                        Text(e.subtitle).font(.app(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(width: 140, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
            }
            if !songs.isEmpty {
                Section("Songs") {
                    ForEach(songs.prefix(300)) { track in
                        TrackRow(track: track) { player.play(songs, startAt: songs.firstIndex(of: track) ?? 0, title: category.title) }
                    }
                }
            }
            ModuleSearchSection(results: online, loading: loading)
        }
        .listStyle(.plain)
        .navigationTitle(category.title)
        .overlay {
            if songs.isEmpty && online.isEmpty && !loading {
                ContentUnavailableView("Nothing in \(category.title) Yet", systemImage: "square.grid.2x2",
                                       description: Text(canDiscover ? "Your extensions found nothing for this category." : "Tag songs with this genre, or connect to search your extensions."))
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
        .task(id: canDiscover) { await loadOnline(seeds: songs) }
    }

    /// Extensions can only search, so each is asked for the artists you play most in this category (new songs only),
    /// plus the category's name, interleaved.
    private func loadOnline(seeds: [Track]) async {
        guard canDiscover else { online = []; return }
        loading = true
        defer { loading = false }
        var plays: [String: Int] = [:]
        for t in seeds where !t.artist.isEmpty && t.artist != "Unknown Artist" { plays[t.artist, default: 0] += (t.playCount ?? 0) + 1 }
        let artists = plays.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        var out: [(InstalledModule, [ModuleTrack])] = []
        for m in ModuleStore.shared.enabled where m.canSearch {
            var lists: [[ModuleTrack]] = []
            for q in artists + [category.online] {
                if Task.isCancelled { return }
                lists.append((try? await ModuleStore.shared.searchTracks(m, q, limit: 12)) ?? [])
            }
            var mixed: [ModuleTrack] = []
            for i in 0..<(lists.map(\.count).max() ?? 0) { for l in lists where i < l.count { mixed.append(l[i]) } }
            let fresh = Array(library.newToYou(mixed).prefix(30))
            if !fresh.isEmpty { out.append((m, fresh)); online = out }
        }
        online = out
    }
}

// MARK: - Shazam

/// A song ShazamKit recognised, and the search it turned into.
struct ShazamHit: Equatable {
    var title: String
    var artist: String
    var artwork: URL?
    var query: String
}

/// Listens with ShazamKit from the search field. The match is put into the search field, so the library and
/// extensions are searched for it like anything typed.
@MainActor
@Observable
final class ShazamListener {
    static let shared = ShazamListener()

    enum Phase: Equatable { case idle, listening, noMatch, denied, failed(String) }
    private(set) var phase: Phase = .idle
    private(set) var hit: ShazamHit?

    @ObservationIgnored private var session: SHManagedSession?
    @ObservationIgnored private var task: Task<Void, Never>?

    var listening: Bool { phase == .listening }

    func toggle(router: Router, player: PlayerModel) {
        if listening { cancel() } else { start(router: router, player: player) }
    }

    func dismiss() { if !listening && phase != .idle { set(.idle) } }

    func cancel() {
        task?.cancel()
        session?.cancel()
        session = nil
        set(.idle)
        restoreAudio()
    }

    /// Every state change animates, so the status row and results slide in and out instead of popping.
    private func set(_ new: Phase) {
        withAnimation(.smooth(duration: 0.35)) { phase = new }
    }

    func start(router: Router, player: PlayerModel) {
        task?.cancel()
        task = Task {
            guard await microphoneAllowed() else { set(.denied); return }
            // The iPhone can't recognise what it is playing itself through the speaker very well, and the
            // microphone needs a recording audio session; the player sets playback back up when it resumes.
            if player.isPlaying { player.pause() }
            let audio = AVAudioSession.sharedInstance()
            try? audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try? audio.setActive(true)
            set(.listening)
            let session = SHManagedSession()
            self.session = session
            let started = ContinuousClock.now
            let timeout = Task {
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { session.cancel() }
            }
            let result = await session.result()
            timeout.cancel()
            guard !Task.isCancelled, self.session === session else { return }
            self.session = nil
            restoreAudio()
            switch result {
            case .match(let match):
                guard let item = match.mediaItems.first, let title = item.title, !title.isEmpty else { set(.noMatch); return }
                let artist = item.artist ?? ""
                let query = artist.isEmpty ? title : "\(title) \(artist)"
                // One animated step: the status row gives way to the match and its results together.
                withAnimation(.smooth(duration: 0.4)) {
                    hit = ShazamHit(title: title, artist: artist, artwork: item.artworkURL, query: query)
                    phase = .idle
                    router.searchText = query
                }
            case .noMatch:
                set(.noMatch)
            case .error(let error, _):
                // Our own 15-second limit ends the session with an error too; that just means nothing was heard.
                let gaveUp = ContinuousClock.now - started >= .seconds(14) || (error as NSError).code == SHError.Code.matchAttemptFailed.rawValue
                set(gaveUp ? .noMatch : .failed(error.localizedDescription))
            @unknown default:
                set(.noMatch)
            }
        }
    }

    private func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    private func restoreAudio() {
        let audio = AVAudioSession.sharedInstance()
        if audio.category != .playback { try? audio.setCategory(.playback, mode: .default) }
    }
}

/// Status row at the top of Search while Shazam listens, or when it found nothing.
struct ShazamStatusSection: View {
    @Environment(Router.self) private var router
    @Environment(PlayerModel.self) private var player
    @Environment(\.openURL) private var openURL
    private var listener: ShazamListener { .shared }

    var body: some View {
        if listener.phase != .idle {
            Section {
                HStack(spacing: 14) {
                    ShazamRings(active: listener.listening)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.app(size: 16, weight: .semibold)).contentTransition(.opacity)
                        Text(detail).font(.app(size: 13)).foregroundStyle(.secondary).contentTransition(.opacity)
                    }
                    Spacer(minLength: 0)
                    switch listener.phase {
                    case .listening:
                        Button("Cancel") { listener.cancel() }.buttonStyle(.glass)
                    case .denied:
                        Button("Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }.buttonStyle(.glass)
                    default:
                        Button("Try Again") { listener.start(router: router, player: player) }.buttonStyle(.glass)
                    }
                }
                .padding(.vertical, 6)
                .listRowSeparator(.hidden)
            }
        }
    }

    private var title: String {
        switch listener.phase {
        case .listening: "Listening…"
        case .noMatch: "No Match"
        case .denied: "Microphone Is Off"
        default: "Couldn’t Recognize"
        }
    }

    private var detail: String {
        switch listener.phase {
        case .listening: "Hold your iPhone near the music."
        case .noMatch: "Try again closer to the music."
        case .denied: "Allow MRSC to use the microphone in Settings."
        case .failed(let message): message
        default: ""
        }
    }
}

/// The Shazam logo with two soft rings spreading out while it listens. Driven by the clock rather than a
/// repeating animation, so it never stutters when the list around it changes.
private struct ShazamRings: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                if active {
                    ForEach(0..<2, id: \.self) { i in
                        let p = (t / 1.8 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(Theme.accent, lineWidth: 1.5)
                            .scaleEffect(1 + p * 0.6)
                            .opacity((1 - p) * 0.55)
                    }
                    .transition(.opacity)
                }
                Image(systemName: "shazam.logo.fill")
                    .font(.app(size: 34))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 40, height: 40)
        }
    }
}

/// What Shazam recognised, with the matching songs from the library. Extension results follow in the usual sections.
struct ShazamResultSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    let hit: ShazamHit

    var body: some View {
        let own = Self.matches(hit, in: library.tracks)
        Section {
            HStack(spacing: 14) {
                AsyncImage(url: hit.artwork) { $0.resizable().scaledToFill() } placeholder: {
                    GeneratedCover(spec: CoverKit.auto(hit.title + hit.artist))
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10 * ThemeStore.shared.current.cornerScale, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title).font(.app(size: 17, weight: .semibold)).lineLimit(2)
                    if !hit.artist.isEmpty { Text(hit.artist).font(.app(size: 14)).foregroundStyle(.secondary).lineLimit(1) }
                    if own.isEmpty { Text("Not in your library").font(.app(size: 12)).foregroundStyle(.tertiary) }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)
            ForEach(own) { track in
                TrackRow(track: track) { player.play(own, startAt: own.firstIndex(of: track) ?? 0, title: hit.title) }
            }
        } header: {
            Label("Shazam", systemImage: "shazam.logo.fill")
                .font(.app(size: 14, weight: .semibold))
                .textCase(nil)
        }
    }

    /// Same song, ignoring "(Remastered)", "- Live" and the like, by the same artist.
    static func matches(_ hit: ShazamHit, in tracks: [Track]) -> [Track] {
        func base(_ s: String) -> String {
            let n = SmartSearch.norm(s)
            let cut = n.firstRange(of: /\s[\(\[]|\s-\s/).map { String(n[..<$0.lowerBound]) } ?? n
            return cut.trimmingCharacters(in: .whitespaces)
        }
        let title = base(hit.title)
        let artist = hit.artist.isEmpty ? nil : hit.artist
        guard !title.isEmpty else { return [] }
        return tracks.filter { t in
            guard base(t.title) == title else { return false }
            guard let artist else { return true }
            return ArtistCatalog.matches(t.artist, name: artist) || ArtistCatalog.matches(artist, name: t.artist)
                || SmartSearch.norm(t.artist).contains(SmartSearch.norm(artist)) || SmartSearch.norm(artist).contains(SmartSearch.norm(t.artist))
        }
    }
}
