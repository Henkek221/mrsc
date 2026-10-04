import SwiftUI

// MARK: - Downloads / offline

struct DownloadsView: View {
    enum Scope: String, CaseIterable, Identifiable { case all = "On This iPhone", downloaded = "Downloaded", streaming = "Not Downloaded"; var id: String { rawValue } }

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadManager.self) private var downloads
    @Environment(SourceManager.self) private var sources
    @State private var scope: Scope = .all
    @State private var confirmRemove = false

    private var tracks: [Track] {
        let scope = scope
        return library.memo("downloads|\(scope.rawValue)") {
            let list: [Track]
            switch scope {
            case .all: list = library.tracks.filter(\.isOffline)
            case .downloaded: list = library.tracks.filter(\.isDownloaded)
            case .streaming: list = library.tracks.filter { $0.isRemote && !$0.isDownloaded }
            }
            return SmartShuffle.libraryOrder(list)
        }
    }

    var body: some View {
        let list = tracks
        List {
            if sources.hasSources || !ModuleStore.shared.modules.isEmpty {
                Picker("Show", selection: $scope) { ForEach(Scope.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
            }
            if downloads.activeCount > 0 {
                Section("Downloading") {
                    ForEach(Array(downloads.states.keys), id: \.self) { id in
                        if let t = library.trackByID[id] { DownloadRow(track: t, state: downloads.state(id)) }
                    }
                    Button("Cancel Remaining", role: .destructive) { downloads.cancelAll() }
                }
            }
            if !list.isEmpty {
                PlayShuffleBar(tracks: list, title: scope.rawValue)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                Section {
                    ForEach(list) { t in
                        TrackRow(track: t) { player.play(list, startAt: list.firstIndex(of: t) ?? 0, title: scope.rawValue) }
                    }
                } footer: {
                    Text("\(songCount(list.count)) · \(ByteCountFormatter.string(fromByteCount: size(list), countStyle: .file))")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if list.isEmpty && downloads.activeCount == 0 {
                ContentUnavailableView(scope == .streaming ? "Everything Is Downloaded" : "No Downloads",
                                       systemImage: "arrow.down.circle",
                                       description: Text("Long-press an album, playlist or artist from your server and choose Download, or tap the arrow next to a song from an extension."))
            }
        }
        .toolbar {
            if scope == .streaming, !list.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { downloads.download(list) } label: { Image(systemName: "arrow.down.circle") }.accessibilityLabel("Download All")
                }
            }
            if scope == .downloaded, !list.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmRemove = true } label: { Image(systemName: "trash") }.accessibilityLabel("Remove Downloads")
                }
            }
        }
        .confirmationDialog("Remove all downloaded songs from this iPhone? They stay in your library for streaming.", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Downloads", role: .destructive) { downloads.removeDownloads(list) }
        }
    }

    private func size(_ list: [Track]) -> Int64 {
        list.reduce(0) { sum, t in
            guard !t.path.isEmpty else { return sum }
            return sum + ((try? FileManager.default.attributesOfItem(atPath: Paths.url(for: t).path)[.size] as? Int64) ?? 0)
        }
    }
}

struct DownloadRow: View {
    let track: Track
    let state: DownloadManager.State?
    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track).thumbnail().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                switch state {
                case .downloading(let p): ProgressView(value: p).tint(Theme.accent)
                case .failed(let m): Text(m).font(.caption).foregroundStyle(.red).lineLimit(1)
                default: Text("Waiting…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Favorites

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let songs = library.memo("favorites.songs") {
            library.tracks.filter(\.isFavorite).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        let entries = (library.playlistEntries + library.albumEntries + library.artistEntries).filter { library.isFavorite($0) }
        List {
            if !entries.isEmpty {
                Section("Collections") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(entries) { e in
                                NavigationLink(value: e.route) {
                                    VStack(spacing: 6) {
                                        ArtworkView(entry: e, radius: 12).thumbnail(340).frame(width: 110, height: 110)
                                        Text(e.title).font(.system(size: 13, weight: .medium)).lineLimit(1).frame(width: 110)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            if !songs.isEmpty {
                Section {
                    PlayShuffleBar(tracks: songs, title: "Favorites").listRowSeparator(.hidden)
                    ForEach(songs) { t in
                        TrackRow(track: t) { player.play(songs, startAt: songs.firstIndex(of: t) ?? 0, title: "Favorites") }
                    }
                } header: { Text("Songs") }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if songs.isEmpty && entries.isEmpty {
                ContentUnavailableView("No Favorites", systemImage: "star", description: Text("Star songs in the player, or long-press artists, albums and playlists."))
            }
        }
    }
}

// MARK: - Radio

struct RadioView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(AppSettings.self) private var settings

    private var topArtists: [LibraryEntry] {
        library.memo("radio.topArtists") {
            library.artistEntries.sorted { a, b in
                a.tracks.reduce(0) { $0 + ($1.playCount ?? 0) } > b.tracks.reduce(0) { $0 + ($1.playCount ?? 0) }
            }.prefix(12).map { $0 }
        }
    }

    private var genres: [(String, [Track])] {
        library.memo("radio.genres") {
            Dictionary(grouping: library.tracks.filter { $0.genre != nil }, by: { $0.genre! })
                .filter { $0.value.count >= 5 }
                .sorted { $0.value.count > $1.value.count }
                .prefix(12).map { ($0.key, $0.value) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    station("Your Station", "Smart shuffle of everything", "sparkles", [.pink, .purple]) {
                        let list = SmartShuffle.order(library.tracks, options: .init(familiarity: max(0.6, settings.shuffleFamiliarity)))
                        player.play(list, title: "Your Station")
                    }
                    station("Discovery", "Songs you've never played", "binoculars.fill", [.teal, .blue]) {
                        let list = library.tracks.filter { ($0.playCount ?? 0) == 0 }.shuffled()
                        player.play(list.isEmpty ? library.tracks.shuffled() : list, title: "Discovery")
                    }
                    station("Favorites Radio", "Starred songs, shuffled", "star.fill", [.orange, .yellow]) {
                        player.play(library.tracks.filter(\.isFavorite), title: "Favorites Radio", shuffled: true)
                    }
                    station("Deep Cuts", "Rarely played album tracks", "opticaldisc.fill", [.indigo, .black]) {
                        let list = library.tracks.filter { ($0.playCount ?? 0) <= 1 && !$0.isFavorite }.shuffled()
                        player.play(Array(list.prefix(100)), title: "Deep Cuts")
                    }
                    if let t = player.current {
                        station("More Like This", t.title, "dot.radiowaves.left.and.right", [Theme.accent, .red]) { player.startStation(from: t) }
                    }
                    let upbeat = library.tracks.filter { ($0.bpm ?? 0) >= 118 }
                    if upbeat.count >= 10 {
                        station("Energy", "Fast songs, beat-matched", "bolt.fill", [.yellow, .red]) {
                            player.play(upbeat.sorted { ($0.bpm ?? 0) < ($1.bpm ?? 0) }, title: "Energy")
                        }
                    }
                    let calm = library.tracks.filter { ($0.bpm ?? 200) < 95 }
                    if calm.count >= 10 {
                        station("Calm", "Slow and easy", "leaf.fill", [.green, .teal]) { player.play(calm, title: "Calm", shuffled: true) }
                    }
                }
                .padding(.horizontal, 16)

                if !topArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Artist Stations").font(.system(size: 22, weight: .bold)).padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(topArtists) { a in
                                    Button { if let seed = a.tracks.randomElement() { player.startStation(from: seed) } } label: {
                                        VStack(spacing: 8) {
                                            ArtworkView(entry: a).thumbnail(370).frame(width: 120, height: 120)
                                                .overlay(alignment: .bottomTrailing) {
                                                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 13, weight: .bold))
                                                        .foregroundStyle(.white).frame(width: 32, height: 32).glassEffect(.regular, in: .circle)
                                                }
                                            Text(a.title).font(.system(size: 13, weight: .medium)).lineLimit(1).frame(width: 120)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !genres.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Genre Stations").font(.system(size: 22, weight: .bold)).padding(.horizontal, 20)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(genres, id: \.0) { g, list in
                                let c = placeholderColors(seed: g)
                                station(g, songCount(list.count), "music.note", [c.0, c.1]) {
                                    player.play(SmartShuffle.order(list, options: .init(familiarity: settings.shuffleFamiliarity)), title: "\(g) Radio")
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Radio")
        .overlay { if library.tracks.isEmpty { ContentUnavailableView("No Music Yet", systemImage: "dot.radiowaves.left.and.right") } }
    }

    private func station(_ title: String, _ subtitle: String, _ icon: String, _ colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                Spacer(minLength: 8)
                Text(title).font(.system(size: 17, weight: .bold)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).opacity(0.8).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 20 * ThemeStore.shared.current.cornerScale, style: .continuous))
        }
        .buttonStyle(PressScale())
        .sensoryFeedback(.impact(weight: .light), trigger: player.queueTitle)
    }
}

// MARK: - Recently played

struct RecentlyPlayedView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let played = library.memo("recentlyPlayed") { library.tracks.filter { $0.lastPlayed != nil }.sorted { $0.lastPlayed! > $1.lastPlayed! } }
        let groups = Dictionary(grouping: played.prefix(300)) { Calendar.current.startOfDay(for: $0.lastPlayed!) }
        List {
            ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                Section(dayTitle(day)) {
                    ForEach(groups[day]!) { t in
                        TrackRow(track: t) { player.play(played, startAt: played.firstIndex(of: t) ?? 0, title: "Recently Played") }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Recently Played")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if played.isEmpty { ContentUnavailableView("Nothing Played Yet", systemImage: "clock") } }
    }

    private func dayTitle(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month())
    }
}

// MARK: - Queue as a tab

struct QueueTabView: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        ZStack {
            LinearGradient(colors: [ArtworkCache.tint(for: player.current), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if player.current == nil {
                ContentUnavailableView("Queue Is Empty", systemImage: "list.bullet", description: Text("Play something to build a queue."))
            } else {
                QueueView().padding(.horizontal, 16)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle("Queue")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { player.undoQueueChange() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!player.canUndo)
            }
        }
    }
}

// MARK: - Track Mix

struct TrackMixView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerModel.self) private var player
    @Environment(AudioLab.self) private var lab
    @Environment(AnalysisService.self) private var analysis

    var body: some View {
        @Bindable var settings = settings
        @Bindable var lab = lab
        List {
            Section {
                Toggle(isOn: $settings.djMode.animation()) { Label("DJ Mode", systemImage: "dial.medium") }
            } footer: {
                Text("DJ Mode turns on everything for real mixes: longer blends that start at the outro, beat matching, bass swaps and matched volume.")
            }

            Section {
                Toggle(isOn: $settings.crossfadeEnabled.animation(.smooth)) { Label("Crossfade", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                if settings.effectiveCrossfade {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text("Transition Length"); Spacer(); Text("\(Int(settings.crossfadeSeconds)) s").foregroundStyle(.secondary).monospacedDigit() }
                        Slider(value: $settings.crossfadeSeconds, in: 1...20, step: 1)
                    }
                    Picker("Curve", selection: $settings.transitionStyle) { ForEach(TransitionStyle.allCases) { Text($0.title).tag($0) } }
                    Picker("Effect", selection: $settings.transitionEffect) { ForEach(TransitionEffect.allCases) { Text($0.title).tag($0) } }
                }
                Toggle(isOn: $settings.gapless) { Label("Gapless Playback", systemImage: "arrow.right.to.line") }
            } header: { Text("Transitions") } footer: {
                Text("Gapless joins songs without a pause when crossfade is off, sample-accurate — perfect for live albums and DJ sets.")
            }

            Section {
                Toggle(isOn: $settings.smartTransitions) { Label("Automatic Intro/Outro Detection", systemImage: "waveform.badge.magnifyingglass") }
                Toggle(isOn: $settings.beatMatch) { Label("Beat-Matched Transitions", systemImage: "metronome") }
                Toggle(isOn: $lab.normalize) { Label("Volume Matching", systemImage: "speaker.wave.2.bubble") }
                Toggle(isOn: $settings.skipSilence) { Label("Skip Silence", systemImage: "forward.end") }
            } header: { Text("Automatic") } footer: {
                Text("Transitions start when a song's outro begins, and the next song comes in on the beat with its tempo matched (within ±8 %).")
            }

            Section {
                Button { player.mixNow() } label: { Label("Mix Into Next Song Now", systemImage: "arrow.triangle.merge") }
                    .disabled(!player.isPlaying)
                if let t = player.current {
                    LabeledContent("Now Playing", value: t.title)
                    LabeledContent("Tempo", value: t.bpm.map { String(format: "%.0f BPM", $0) } ?? "Not measured")
                    LabeledContent("Loudness", value: t.loudness.map { String(format: "%.1f LUFS", $0) } ?? "Not measured")
                    if let o = t.outroStart, t.duration > 0 { LabeledContent("Outro Starts", value: formatTime(o)) }
                }
            } header: { Text("Manual") }

            Section {
                if analysis.running {
                    HStack {
                        ProgressView()
                        Text("Analyzing \(analysis.done + 1) of \(max(analysis.total, analysis.done + 1))…").foregroundStyle(.secondary)
                    }
                } else {
                    let pending = analysis.pendingCount
                    Button { analysis.analyzeLibrary() } label: { Label(pending == 0 ? "All Songs Analyzed" : "Analyze \(songCount(pending))", systemImage: "waveform") }
                        .disabled(pending == 0)
                }
            } header: { Text("Analysis") } footer: {
                Text("Tempo, beats, loudness and silence are measured on this iPhone. Streaming songs are measured once they're cached or downloaded.")
            }
        }
        .navigationTitle("Track Mix")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sources (Jellyfin, Subsonic)

struct SourcesView: View {
    @Environment(SourceManager.self) private var sources
    @Environment(AppSettings.self) private var settings
    @State private var adding: SourceKind?
    @State private var addingModule = false
    @State private var searchingOctave: SourceAccount?
    @State private var cacheSize: Int64 = 0
    @AppStorage("streamCacheMB") private var cacheMB = 1024

    var body: some View {
        @Bindable var sources = sources
        @Bindable var settings = settings
        List {
            Section {
                ForEach(sources.accounts) { acc in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            GradientIcon(symbol: acc.kind.symbol, colors: [Color(red: 0.55, green: 0.3, blue: 0.95), Color(red: 0.1, green: 0.6, blue: 0.95)], size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(acc.name).font(.headline)
                                Text("\(acc.userName) · \(URL(string: acc.baseURL)?.host() ?? acc.baseURL)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if sources.syncing.contains(acc.id) { ProgressView() }
                        }
                        HStack {
                            Text("\(acc.trackCount) songs").font(.caption).foregroundStyle(.secondary)
                            if let d = acc.lastSync { Text("· synced \(d.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                        }
                        if let e = sources.lastError[acc.id] { Text(e).font(.caption).foregroundStyle(.red) }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { sources.remove(acc.id) }
                        Button("Sync") { Task { await sources.sync(acc.id) } }.tint(.blue)
                    }
                    .contextMenu {
                        if acc.kind == .octave {
                            Button { searchingOctave = acc } label: { Label("Search Octave", systemImage: "magnifyingglass") }
                        }
                        Button { Task { await sources.sync(acc.id) } } label: { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath") }
                        Button { sources.setEnabled(acc.id, !acc.enabled) } label: { Label(acc.enabled ? "Pause Source" : "Resume Source", systemImage: acc.enabled ? "pause" : "play") }
                        Button(role: .destructive) { sources.remove(acc.id) } label: { Label("Remove Server", systemImage: "trash") }
                    }
                }
                ForEach(sources.accounts.filter { $0.kind == .octave && $0.enabled }) { acc in
                    Button { searchingOctave = acc } label: { Label("Search Octave", systemImage: "magnifyingglass") }
                }
                Menu {
                    ForEach(SourceKind.allCases) { kind in
                        Button { adding = kind } label: { Label(kind.title, systemImage: kind.symbol) }
                    }
                } label: { Label("Add Server", systemImage: "plus.circle.fill") }
                if sources.hasSources {
                    Button { Task { await sources.syncAll() } } label: { Label("Sync All Now", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(!sources.syncing.isEmpty)
                }
            } header: { Text("Servers") } footer: {
                Text("Songs from your server join your library next to local files — one library, one app. Subsonic works with Navidrome, Gonic, Airsonic, Ampache, Nextcloud Music and other compatible servers.")
            }

            ModulesSection(adding: $addingModule)

            if sources.hasSources || !ModuleStore.shared.modules.isEmpty {
                Section("Streaming") {
                    Picker("Wi-Fi Quality", selection: $sources.streamBitrate) { qualityOptions }
                    Picker("Cellular Quality", selection: $sources.cellularBitrate) { qualityOptions }
                    Picker("Download Quality", selection: $sources.downloadBitrate) { qualityOptions }
                    Toggle("Sync on Launch", isOn: $sources.autoSync)
                    Toggle("Skip Songs I Have Locally", isOn: $sources.skipLocalDuplicates)
                }
                Section {
                    Toggle(isOn: $settings.offlineMode) { Label("Offline Mode", systemImage: "icloud.slash") }
                    Picker("Stream Cache", selection: $cacheMB) {
                        Text("256 MB").tag(256); Text("512 MB").tag(512); Text("1 GB").tag(1024); Text("2 GB").tag(2048); Text("5 GB").tag(5120)
                    }
                    LabeledContent("Cache in Use", value: ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                    Button("Clear Stream Cache", role: .destructive) { StreamCache.clear(); cacheSize = 0 }
                    if !sources.pending.isEmpty {
                        LabeledContent("Waiting to Sync", value: "\(sources.pending.count) changes")
                    }
                } header: { Text("Offline") } footer: {
                    Text("Offline Mode only plays music on this iPhone. Favorites and plays made offline are sent to your server when you're back online.")
                }
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .task { cacheSize = await Task.detached { StreamCache.size }.value }
        .sheet(item: $adding) { ServerLoginView(kind: $0) }
        .sheet(isPresented: $addingModule) { AddModuleSheet() }
        .sheet(item: $searchingOctave) { OctaveSearchView(account: $0) }
    }

    @ViewBuilder private var qualityOptions: some View {
        Text("Original").tag(0)
        Text("320 kbps").tag(320)
        Text("256 kbps").tag(256)
        Text("192 kbps").tag(192)
        Text("128 kbps").tag(128)
    }
}

struct ServerLoginView: View {
    let kind: SourceKind
    /// Pushed inside another flow (Add Music) instead of presented as its own sheet.
    var embedded = false
    @Environment(SourceManager.self) private var sources
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var user = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        if embedded { form } else { NavigationStack { form } }
    }

    private var form: some View {
        Form {
            Section {
                if kind == .octave {
                    LabeledContent("API", value: "api.octavestreaming.com")
                    SecureField("Octave Account Key", text: $password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Link("Open Octave Account Settings", destination: URL(string: "https://music.octavestreaming.com")!)
                } else {
                TextField("Server Address", text: $server, prompt: Text(kind == .jellyfin ? "jellyfin.local:8096" : "navidrome.local:4533"))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.URL)
                TextField("User Name", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.username)
                SecureField("Password", text: $password).textContentType(.password)
                }
            } footer: {
                Text(kind == .octave ? "Copy your account key from Octave’s account settings. MRSC stores it in the Keychain. Playlists and recent songs are imported; favorites and listening history changed in MRSC stay on this device." : kind == .jellyfin
                     ? "Your password is only used to sign in; MRSC keeps the access token in the Keychain."
                     : "Subsonic servers check the password on every request, so MRSC keeps it in the Keychain and sends a salted hash where the server supports it.")
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(working)
        .toolbar {
            if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                if working { ProgressView() } else {
                    Button("Sign In") {
                        working = true
                        error = nil
                        Task {
                            do {
                                switch kind {
                                case .jellyfin: try await sources.addJellyfin(server: server, user: user, password: password)
                                case .subsonic: try await sources.addSubsonic(server: server, user: user, password: password)
                                case .octave: try await sources.addOctave(key: password)
                                }
                                dismiss()
                            } catch let e {
                                error = e.localizedDescription
                            }
                            working = false
                        }
                    }
                    .disabled(kind == .octave ? password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : server.isEmpty || user.isEmpty)
                }
            }
        }
    }
}

struct OctaveSearchView: View {
    let account: SourceAccount
    @Environment(SourceManager.self) private var sources
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [OctaveClient.Song] = []
    @State private var imported = Set<String>()
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search songs or artists", text: $query)
                        .submitLabel(.search)
                        .onSubmit { search() }
                    Button("Search", action: search)
                        .disabled(working || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if working { ProgressView() }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section("Songs") {
                    ForEach(results) { song in
                        Button {
                            sources.importOctave([song], sourceID: account.id)
                            imported.insert(song.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(song.title).foregroundStyle(.primary)
                                    Text("\(song.artist.name) · \(song.album.title)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: imported.contains(song.id) ? "checkmark.circle.fill" : "plus.circle")
                            }
                        }
                        .disabled(imported.contains(song.id))
                        .accessibilityLabel("\(song.title), \(song.artist.name), \(imported.contains(song.id) ? "Added" : "Add to library")")
                    }
                }
            }
            .navigationTitle("Search Octave")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func search() {
        guard !working, let client = sources.client(for: account.id) as? OctaveClient else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        working = true; error = nil
        Task {
            defer { working = false }
            do { results = try await client.search(text) }
            catch { results = []; self.error = error.localizedDescription }
        }
    }
}
