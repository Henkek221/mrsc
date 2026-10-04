import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let eightSpineModule = UTType(importedAs: "com.ecki.mrsc.8spine-module", conformingTo: .plainText)
}

// MARK: - Section inside Sources

struct ModulesSection: View {
    /// Community invite shown under Server Extensions. nil hides the link.
    static let discord: URL? = Links.discord
    private var store: ModuleStore { ModuleStore.shared }
    /// Presented by the page, not the section: sheets on list sections can close the whole settings sheet.
    @Binding var adding: Bool

    var body: some View {
        Section {
            ForEach(store.modules) { m in
                NavigationLink { ModuleDetailView(moduleID: m.id) } label: { ModuleRow(module: m) }
                    .swipeActions { Button("Remove", role: .destructive) { store.remove(m.id) } }
            }
            ForEach(store.repos) { repo in
                NavigationLink { ModuleRepoView(repoURL: repo.url) } label: {
                    Label("\(repo.name) · \(repo.entries.count) extensions", systemImage: "square.stack.3d.down.right")
                }
                .swipeActions { Button("Remove", role: .destructive) { store.removeRepo(repo.url) } }
            }
            Button { adding = true } label: { Label("Add Extension…", systemImage: "puzzlepiece.extension.fill") }
        } header: { Text("Server Extensions") } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("For developers: an extension is a small JavaScript file that connects MRSC to a music server or API. Its songs join your library like songs from Jellyfin. MRSC doesn't include any extensions. Only add extensions from developers you trust, because an extension can connect to any server.")
                if let discord = Self.discord {
                    Link("Not sure what this is? Join the Discord", destination: discord)
                }
            }
        }
    }
}

/// One place to add anything: a module link, a repository link (index.json / module-source.json), pasted code or a file.
struct AddModuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var store: ModuleStore { ModuleStore.shared }
    @State private var input = ""
    @State private var working = false
    @State private var result: Result?
    @State private var repoURL: String?
    @State private var importingFile = false
    @FocusState private var focused: Bool

    enum Result { case installed(String), repo(String, Int), failed(String) }

    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var looksLikeLink: Bool { Self.isLink(trimmed) }
    private static func isLink(_ s: String) -> Bool {
        let head = s.prefix(12).lowercased()
        return head.hasPrefix("http") || head.hasPrefix("eightspine:") || head.hasPrefix("mrsc:")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link, repository or extension code", text: $input, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($focused)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 15, design: looksLikeLink || input.isEmpty ? .default : .monospaced))
                    HStack {
                        PasteButton(payloadType: String.self) { items in
                            guard let s = items.first else { return }
                            if Self.isLink(s) { input = s }
                            Task { await add(s) }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        Spacer()
                        Button { importingFile = true } label: { Label("File…", systemImage: "doc") }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                } footer: {
                    Text("Paste a link to an extension (.js), a repository (index.json or module-source.json, GitHub links work) or the extension code itself. MRSC works out which one it is.")
                }

                if let result {
                    Section {
                        switch result {
                        case .installed(let name):
                            Label("Installed \(name)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .repo(let name, let count):
                            Label("Added \(name) with \(count) extensions", systemImage: "square.stack.3d.down.right.fill").foregroundStyle(.green)
                            if let repoURL {
                                NavigationLink("Choose Extensions to Install") { ModuleRepoView(repoURL: repoURL) }
                            }
                        case .failed(let message):
                            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Text("Only add extensions from developers you trust. An extension can connect to any server.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Extension")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Add") { Task { await add() } }.disabled(trimmed.isEmpty)
                    }
                }
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.eightSpineModule, .javaScript, .json, .plainText, .data]) { r in
                guard case .success(let url) = r else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) { Task { await add(text) } }
            }
            // Code pasted into the field gets installed right away: thousands of lines in a TextField make the sheet lag.
            .onChange(of: input) { _, new in
                guard new.utf8.count > 2000, !Self.isLink(new) else { return }
                input = ""
                Task { await add(new) }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    /// `raw` is code or a link from a file or the paste button; it never goes into the text field.
    private func add(_ raw: String? = nil) async {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        guard !text.isEmpty else { return }
        working = true
        result = nil
        defer { working = false }
        do {
            if Self.isLink(text) {
                var url: URL?
                if let deep = URL(string: text), let prompt = ModuleInstallPrompt.from(deep) { url = prompt.url } else { url = URL(string: text) }
                guard let url else { result = .failed("That link isn't valid."); return }
                // Repository index?
                if url.pathExtension.lowercased() == "json" {
                    let repo = try await store.addRepo(url)
                    repoURL = repo.url
                    result = .repo(repo.name, repo.entries.count)
                    return
                }
                let m = try await store.install(from: url)
                result = .installed(m.name)
            } else if text.hasPrefix("{") || text.hasPrefix("[") {
                result = .failed("That's a repository list. Paste its link instead, so MRSC can download the extensions next to it.")
            } else {
                let m = try store.install(code: text, sourceURL: nil)
                result = .installed(m.name)
            }
        } catch {
            if case ModuleError.invalid(let msg) = error, msg.contains("was added under Repositories") {
                repoURL = store.repos.last?.url
                result = .repo(store.repos.last?.name ?? "Repository", store.repos.last?.entries.count ?? 0)
            } else {
                result = .failed(error.localizedDescription)
            }
        }
    }
}

struct ModuleRow: View {
    let module: InstalledModule
    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(symbol: "puzzlepiece.extension.fill", colors: [.orange, .pink], size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(module.name).font(.headline)
                    if !module.version.isEmpty { Text(module.version).font(.caption).foregroundStyle(.secondary) }
                }
                if !module.labels.isEmpty {
                    Text(module.labels.prefix(4).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if !module.enabled { Text("Off").font(.caption).foregroundStyle(.secondary) }
        }
        .opacity(module.enabled ? 1 : 0.55)
    }
}

// MARK: - Extension detail

struct ModuleDetailView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss
    let moduleID: String
    private var store: ModuleStore { ModuleStore.shared }
    @State private var query = ""
    @State private var results: [ModuleTrack] = []
    @State private var searching = false
    @State private var error: String?
    @State private var confirmRemove = false

    var body: some View {
        if let m = store.module(moduleID) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.name).font(.title3.bold())
                        Text([m.version.isEmpty ? nil : "Version \(m.version)", m.author.map { "by \($0)" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if let d = m.detail { Text(d).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 4)
                    Toggle("Enabled", isOn: Binding(get: { m.enabled }, set: { store.setEnabled(m.id, $0) }))
                    LabeledContent("Can", value: [m.canSearch ? "Search" : nil, m.canStream ? "Stream" : nil, m.canAlbum ? "Albums" : nil].compactMap { $0 }.joined(separator: ", "))
                    LabeledContent("Songs in Library", value: "\(library.tracks.filter { $0.sourceID == m.sourceID }.count)")
                }

                if !m.settings.isEmpty {
                    Section("Settings") {
                        ForEach(m.settings) { s in setting(m, s) }
                    }
                }

                if m.canSearch {
                    Section {
                        HStack {
                            TextField("Try a search", text: $query).submitLabel(.search).onSubmit { Task { await search(m) } }
                                .autocorrectionDisabled()
                            if searching { ProgressView() } else {
                                Button("Search") { Task { await search(m) } }.disabled(query.isEmpty)
                            }
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        ForEach(results) { r in ModuleResultRow(track: r) }
                    } header: { Text("Test") }
                }

                Section {
                    if store.logs.isEmpty { Text("No messages yet.").foregroundStyle(.secondary) }
                    ForEach(Array(store.logs.suffix(40).reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(line.contains("ERROR") ? .red : .secondary)
                    }
                } header: {
                    HStack { Text("Log"); Spacer(); Button("Clear") { store.clearLogs() }.font(.caption) }
                }

                Section {
                    if let src = m.sourceURL, let url = URL(string: src) {
                        Button { Task { _ = try? await store.install(from: url) } } label: { Label("Update from Link", systemImage: "arrow.triangle.2.circlepath") }
                    }
                    Button("Remove Extension", role: .destructive) { confirmRemove = true }
                }
            }
            .navigationTitle(m.name)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Remove \(m.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove Extension Only", role: .destructive) { store.remove(m.id); dismiss() }
                Button("Remove Extension and Its Songs", role: .destructive) {
                    let ids = Set(library.allTracks.filter { $0.sourceID == m.sourceID && !$0.isDownloaded }.map(\.id))
                    library.delete(ids)
                    store.remove(m.id)
                    dismiss()
                }
            } message: { Text("Downloaded songs keep playing without the extension.") }
        } else {
            ContentUnavailableView("Extension Removed", systemImage: "puzzlepiece.extension")
        }
    }

    @ViewBuilder private func setting(_ m: InstalledModule, _ s: ModuleSetting) -> some View {
        let current = store.value(m, s)
        VStack(alignment: .leading, spacing: 2) {
            switch s.type {
            case "toggle", "switch", "boolean", "bool":
                Toggle(s.label, isOn: Binding(get: { current == "true" }, set: { store.setValue(m.id, key: s.key, json: $0 ? "true" : "false") }))
            case "text", "input", "string", "password":
                TextField(s.label, text: Binding(
                    get: { (try? JSONSerialization.jsonObject(with: Data(current.utf8), options: .fragmentsAllowed) as? String) ?? "" },
                    set: { store.setValue(m.id, key: s.key, json: ModuleStore.jsString($0)) }))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            default:
                Picker(s.label, selection: Binding(get: { current }, set: { store.setValue(m.id, key: s.key, json: $0) })) {
                    ForEach(s.options, id: \.value) { Text($0.label).tag($0.value) }
                }
            }
            if let d = s.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func search(_ m: InstalledModule) async {
        searching = true
        error = nil
        defer { searching = false }
        do { results = try await store.searchTracks(m, query, limit: 20) } catch { self.error = error.localizedDescription; results = [] }
    }
}

// MARK: - Repository

struct ModuleRepoView: View {
    let repoURL: String
    private var store: ModuleStore { ModuleStore.shared }
    @State private var busy: String?
    @State private var message: String?

    var body: some View {
        let repo = store.repos.first { $0.url == repoURL }
        List {
            ForEach(repo?.entries ?? []) { e in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(e.name).font(.headline)
                            Text(e.version).font(.caption).foregroundStyle(.secondary)
                        }
                        if let d = e.description { Text(d.capitalized(with: nil)).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                        if !e.tags.isEmpty { Text(e.tags.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary) }
                    }
                    Spacer()
                    if busy == e.id { ProgressView() } else if e.locked == true {
                        Label("Not supported", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    } else {
                        let installed = store.module(e.id) != nil
                        Button(installed ? "Update" : "Install") { Task { await install(e) } }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .overlay {
            if let r = repo, !r.entries.isEmpty, r.entries.allSatisfy({ $0.locked == true }) {
                VStack { Spacer()
                    Text("The extensions here are in a locked format that MRSC can't run.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                }
            }
        }
        .navigationTitle(repo?.name ?? "Repository")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { if let url = URL(string: repoURL) { _ = try? await store.addRepo(url) } }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} }
    }

    private func install(_ e: ModuleRepo.Entry) async {
        guard let url = URL(string: e.url) else { return }
        busy = e.id
        defer { busy = nil }
        do { let m = try await store.install(from: url); message = "Installed \(m.name)." } catch { message = error.localizedDescription }
    }
}

// MARK: - Results

struct ModuleResultRow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadManager.self) private var downloads
    let track: ModuleTrack
    var others: [ModuleTrack] = []
    @State private var picking: [UUID]?
    @State private var artistPage: String?

    var body: some View {
        let saved = library.moduleTrack(track)
        HStack(spacing: 12) {
            Button {
                let queue = [track] + others.filter { $0.id != track.id }.prefix(30)
                player.play(library.addModuleTracks(queue), title: "Search")
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: track.cover.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: {
                        GeneratedCover(spec: CoverKit.auto(track.album + track.artist))
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8 * ThemeStore.shared.current.cornerScale, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.system(size: 16, weight: .medium)).lineLimit(1).foregroundStyle(.primary)
                        Text("\(track.artist)" + (track.duration > 0 ? " • \(formatTime(track.duration))" : "")).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            downloadButton(saved)
            Menu {
                if !track.artist.isEmpty, track.artist != "Unknown Artist" {
                    Button { artistPage = track.artist } label: { Label("Show Artist", systemImage: "music.mic") }
                }
                Button { player.playNext([library.addModuleTrack(track)]) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { player.playAfter([library.addModuleTrack(track)]) } label: { Label("Play After", systemImage: "text.line.last.and.arrowtriangle.forward") }
                Button { picking = [library.addModuleTrack(track).id] } label: { Label("Add to Playlist…", systemImage: "text.badge.plus") }
                Button { _ = library.addModuleTrack(track, keep: true) } label: { Label("Add to Library", systemImage: "plus") }
                if let saved, saved.isDownloaded {
                    Button { downloads.removeDownloads([saved]) } label: { Label("Remove Download", systemImage: "xmark.circle") }
                } else {
                    Button { download() } label: { Label("Download", systemImage: "arrow.down.circle") }
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 36, height: 44).contentShape(Rectangle())
            }
        }
        .swipeActions(edge: .leading) {
            if saved?.isDownloaded != true {
                Button { download() } label: { Label("Download", systemImage: "arrow.down.circle") }.tint(Theme.accent)
            }
        }
        .sheet(item: Binding(get: { picking.map { IDList(ids: $0) } }, set: { picking = $0?.ids })) { PlaylistPicker(trackIDs: $0.ids) }
        .navigationDestination(item: $artistPage) { ModuleArtistView(name: $0).themedBackground() }
    }

    private func download() { downloads.download([library.addModuleTrack(track, keep: true)]) }

    /// Shows whether the song is on this iPhone; tap to save it for offline listening (or to retry).
    private func downloadButton(_ saved: Track?) -> some View {
        let phase = downloads.phase(saved)
        return Button { download() } label: {
            DownloadIndicator(phase: phase, size: 22)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(phase == .idle || phase == .failed)
    }

    private struct IDList: Identifiable { let ids: [UUID]; var id: String { ids.map(\.uuidString).joined() } }
}

/// Extension results in Search. The search itself runs in SearchView so it starts even before there are results.
struct ModuleSearchSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads
    let results: [(InstalledModule, [ModuleTrack])]
    let loading: Bool

    var body: some View {
        if loading && results.isEmpty {
            Section { HStack { ProgressView(); Text("Searching extensions…").foregroundStyle(.secondary) } }
        }
        ForEach(results, id: \.0.id) { m, tracks in
            Section {
                ForEach(tracks) { t in ModuleResultRow(track: t, others: tracks) }
            } header: {
                HStack {
                    Label("From \(m.name)", systemImage: "puzzlepiece.extension")
                    Spacer()
                    if m.canStream {
                        Button("Download All") { downloads.download(tracks.map { library.addModuleTrack($0, keep: true) }) }
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .textCase(nil)
            }
        }
    }
}

// MARK: - Install from deep link / file

struct ModuleInstallPrompt: Identifiable {
    let url: URL
    var id: String { url.absoluteString }

    /// eightspine://…, mrsc://module?url=…, or any link with an http(s) URL inside.
    static func from(_ link: URL) -> ModuleInstallPrompt? {
        let s = link.absoluteString.removingPercentEncoding ?? link.absoluteString
        guard ["eightspine", "mrsc"].contains(link.scheme?.lowercased() ?? "") else { return nil }
        if let comps = URLComponents(url: link, resolvingAgainstBaseURL: false),
           let q = comps.queryItems?.first(where: { ["url", "module", "src", "link"].contains($0.name.lowercased()) })?.value,
           let u = URL(string: q), u.scheme?.hasPrefix("http") == true { return .init(url: u) }
        if let r = s.range(of: #"https?:(//)?[^\s]+"#, options: .regularExpression) {
            var found = String(s[r])
            if !found.contains("://") { found = found.replacingOccurrences(of: "https:", with: "https://").replacingOccurrences(of: "http:", with: "http://") }
            if let u = URL(string: found) { return .init(url: u) }
        }
        return nil
    }
}

struct ModuleInstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    let prompt: ModuleInstallPrompt
    @State private var working = false
    @State private var result: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
                Text("Add Extension?").font(.title2.bold())
                Text(prompt.url.absoluteString).font(.footnote.monospaced()).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("Only add extensions from developers you trust. An extension can connect to any server.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let result { Text(result).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center) }
                Spacer()
                if result == nil {
                    Button {
                        working = true
                        Task {
                            do { let m = try await ModuleStore.shared.install(from: prompt.url); result = "Installed \(m.name)." }
                            catch { result = error.localizedDescription }
                            working = false
                        }
                    } label: { Group { if working { ProgressView() } else { Text("Add") } }.frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.glassProminent)
                    .disabled(working)
                }
            }
            .padding(24)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(result == nil ? "Cancel" : "Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}


// MARK: - Artist from extensions

/// All songs the extensions offer for one artist, under a header with who they are (photo and basics from Wikipedia).
/// Opened from "Show Artist" or the Artists section in Search.
struct ModuleArtistView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(AppSettings.self) private var settings
    let name: String
    @State private var tracks: [ModuleTrack] = []
    @State private var loading = true
    @State private var about: AboutInfo?
    @State private var titleShown = false

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 14, trailing: 20))
            if loading && tracks.isEmpty {
                HStack { ProgressView(); Text("Loading songs…").foregroundStyle(.secondary) }
            } else if tracks.isEmpty {
                ContentUnavailableView("No songs found", systemImage: "music.note", description: Text("No extension has songs by \(name)."))
                    .listRowSeparator(.hidden)
            }
            ForEach(tracks) { ModuleResultRow(track: $0, others: tracks) }
            if let about {
                AboutCard(info: about)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 12, trailing: 20))
            }
        }
        .listStyle(.plain)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > (about?.imageURL == nil ? 90 : 260) } action: { _, shown in
            withAnimation(.easeOut(duration: 0.2)) { titleShown = shown }
        }
        .navigationTitle(titleShown ? name : "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task(id: name) {
            let info = await AboutInfo.artist(name, settings: settings)
            withAnimation(.smooth) { about = info }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            if let url = about?.imageURL {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.primary.opacity(0.06) }
                    .frame(width: 168, height: 168)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .accessibilityHidden(true)
            }
            VStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let line = subtitle {
                    Text(line)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            if !tracks.isEmpty {
                HStack(spacing: 12) {
                    Button { play(shuffled: false) } label: {
                        Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button { play(shuffled: true) } label: {
                        Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.glass)
                }
                .font(.system(size: 17, weight: .semibold))
                .controlSize(.large)
                .tint(Theme.accent)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "Formed 1988 in Sacramento · 24 songs"
    private var subtitle: String? {
        var parts = about?.facts ?? []
        if !tracks.isEmpty { parts.append(songCount(tracks.count)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func play(shuffled: Bool) {
        let list = library.addModuleTracks(tracks)
        player.play(list, title: name, shuffled: shuffled)
    }

    private func load() async {
        let key = SmartSearch.norm(name)
        var out: [ModuleTrack] = []
        var seen = Set<String>()
        for (_, found) in await ModuleStore.shared.search(name, limit: 50) {
            for t in found where SmartSearch.norm(t.artist).contains(key) && seen.insert("\(t.moduleID)|\(t.trackID)").inserted { out.append(t) }
        }
        tracks = out
        loading = false
    }
}
