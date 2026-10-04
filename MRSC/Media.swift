import Foundation
import Observation
import UniformTypeIdentifiers

// MARK: - Where the audio of a song lives

nonisolated enum MediaLocator {
    /// A file AVAudioFile can open right now, or nil when a streaming song still has to be fetched.
    static func localURL(for track: Track) -> URL? {
        if !track.path.isEmpty { return Paths.url(for: track) }
        return StreamCache.url(for: track.id)
    }

    static func isPlayableNow(_ track: Track) -> Bool { localURL(for: track) != nil }

    static func fileExtension(mime: String?, fallback: String = "mp3") -> String {
        switch mime?.lowercased().split(separator: ";").first.map(String.init) ?? "" {
        case "audio/mpeg", "audio/mp3": "mp3"
        case "audio/flac", "audio/x-flac": "flac"
        case "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac", "audio/x-aac": "m4a"
        case "audio/wav", "audio/x-wav", "audio/wave": "wav"
        case "audio/aiff", "audio/x-aiff": "aif"
        default: fallback
        }
    }
}

// MARK: - Streaming cache

/// Streaming songs are fetched completely before they play, so the whole audio engine (EQ, crossfade,
/// beat matching, Audio Lab) works for them exactly like for local files. Upcoming songs are prefetched.
nonisolated enum StreamCache {
    static let extensions = ["mp3", "m4a", "flac", "wav", "aif", "aac", "caf", "mp4"]

    static var limitBytes: Int64 {
        let mb = UserDefaults.standard.object(forKey: "streamCacheMB") as? Int ?? 1024
        return Int64(mb) * 1_048_576
    }

    static func url(for id: UUID) -> URL? {
        for ext in extensions {
            let u = Paths.streamCache.appendingPathComponent("\(id.uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    static func remove(_ id: UUID) {
        if let u = url(for: id) { try? FileManager.default.removeItem(at: u) }
    }

    static func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    static var size: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.streamCache, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    static func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.streamCache, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    /// Deletes the least recently used files until the cache fits, never touching `keep`.
    static func trim(keep: Set<UUID>) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        var files = (try? FileManager.default.contentsOfDirectory(at: Paths.streamCache, includingPropertiesForKeys: keys)) ?? []
        files.sort {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        var total = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        for f in files where total > limitBytes {
            let id = UUID(uuidString: f.deletingPathExtension().lastPathComponent)
            if let id, keep.contains(id) { continue }
            total -= Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// Downloads to `dir/<id>.<ext>` and returns the file.
    @concurrent
    static func download(_ request: URLRequest, id: UUID, to dir: URL,
                         progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let delegate = ProgressDelegate(progress)
        let (tmp, resp) = try await URLSession.shared.download(for: request, delegate: delegate)
        let http = resp as? HTTPURLResponse
        guard let code = http?.statusCode, (200..<300).contains(code) else {
            try? FileManager.default.removeItem(at: tmp)
            throw SourceError.server(http?.statusCode ?? 0)
        }
        let mime = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if mime.contains("mpegurl") || mime.contains("dash+xml") || mime.hasPrefix("text/html") || mime.contains("json") {
            try? FileManager.default.removeItem(at: tmp)
            throw ModuleError.invalid("the stream is a \(mime) playlist, not an audio file")
        }
        let ext = MediaLocator.fileExtension(mime: http?.value(forHTTPHeaderField: "Content-Type"),
                                             fallback: ["flac", "mp3", "m4a", "wav", "aac"].first { request.url?.pathExtension.lowercased() == $0 } ?? "mp3")
        let dest = dir.appendingPathComponent("\(id.uuidString).\(ext)")
        for e in extensions { try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id.uuidString).\(e)")) }
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let report: (@Sendable (Double) -> Void)?
        /// Last value passed on; the session calls back serially, so no lock is needed.
        private var last = -1.0
        init(_ report: (@Sendable (Double) -> Void)?) { self.report = report }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            // Every chunk would redraw every row showing download state; whole percents are plenty.
            guard p - last >= 0.01 || p >= 1 else { return }
            last = p
            report?(p)
        }
    }
}

/// Fetches streaming songs into the cache, sharing one download between "play" and "prefetch".
@MainActor
final class StreamLoader {
    static let shared = StreamLoader()
    var sources: SourceManager?
    private var inflight: [UUID: Task<URL, Error>] = [:]

    func fetch(_ track: Track) async throws -> URL {
        if let url = MediaLocator.localURL(for: track) {
            if track.path.isEmpty { StreamCache.touch(url) }
            return url
        }
        if let task = inflight[track.id] { return try await task.value }
        guard NetworkMonitor.shared.isOnline else { throw SourceError.offline }
        let req = try await request(for: track, download: false)
        let id = track.id
        let task = Task { try await StreamCache.download(req, id: id, to: Paths.streamCache) }
        inflight[id] = task
        defer { inflight[id] = nil }
        let url = try await task.value
        return url
    }

    /// Whether a streaming song can be fetched right now (server signed in, or module installed and on).
    func canStream(_ t: Track) -> Bool {
        guard t.isRemote else { return false }
        if let m = ModuleStore.shared.module(forSource: t.sourceID) { return m.enabled && m.canStream }
        return sources?.client(for: t.sourceID) != nil
    }

    /// The audio request for a streaming song: Jellyfin builds it directly, modules are asked for a fresh link.
    func request(for track: Track, download: Bool) async throws -> URLRequest {
        guard let remoteID = track.remoteID else { throw SourceError.unauthorized }
        if let m = ModuleStore.shared.module(forSource: track.sourceID) {
            let kbps = download ? (sources?.downloadBitrate ?? 0) : (NetworkMonitor.shared.isExpensive ? (sources?.cellularBitrate ?? 192) : (sources?.streamBitrate ?? 320))
            let quality = kbps == 0 ? "LOSSLESS" : kbps >= 256 ? "HIGH" : "LOW"
            let url = try await ModuleStore.shared.streamURL(moduleID: m.id, trackID: remoteID, quality: quality)
            var req = URLRequest(url: url)
            req.timeoutInterval = 60
            return req
        }
        if let client = sources?.client(for: track.sourceID) as? OctaveClient {
            return try await client.playbackRequest(remoteID: remoteID, maxBitrate: sources?.bitrate(forDownload: download))
        }
        guard let client = sources?.client(for: track.sourceID),
              let req = client.audioRequest(remoteID: remoteID, maxBitrate: sources?.bitrate(forDownload: download)) else {
            throw SourceError.unauthorized
        }
        return req
    }

    func prefetch(_ tracks: [Track], keep: Set<UUID>) {
        for t in tracks where t.isRemote && !MediaLocator.isPlayableNow(t) && inflight[t.id] == nil {
            Task { _ = try? await fetch(t) }
        }
        Task.detached(priority: .background) { StreamCache.trim(keep: keep) }
    }
}

// MARK: - Downloads (offline copies of streaming songs)

@Observable
final class DownloadManager {
    enum State: Equatable {
        case queued, downloading(Double), failed(String)
        var isFailed: Bool { if case .failed = self { true } else { false } }
    }

    private(set) var states: [UUID: State] = [:]
    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var running = 0
    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored let sources: SourceManager

    init(library: LibraryStore, sources: SourceManager) {
        self.library = library
        self.sources = sources
    }

    var activeCount: Int { states.values.filter { !$0.isFailed }.count }

    func state(_ id: UUID) -> State? { states[id] }

    func download(_ tracks: [Track]) {
        for t in tracks where t.isRemote && !t.isDownloaded {
            // Failed downloads can be tried again; queued/running ones are left alone.
            if let s = states[t.id], !s.isFailed { continue }
            states[t.id] = .queued
            queue.append(t.id)
        }
        pump()
    }

    func cancelAll() {
        for id in queue { states[id] = nil }
        queue.removeAll()
    }

    func removeDownloads(_ tracks: [Track]) {
        let ids = Set(tracks.filter(\.isDownloaded).map(\.id))
        for t in tracks where t.isDownloaded { try? FileManager.default.removeItem(at: Paths.url(for: t)) }
        library.updateMany(ids) { $0.path = "" }
    }

    private func pump() {
        while running < 2, !queue.isEmpty {
            let id = queue.removeFirst()
            guard let track = library.trackByID[id] else { states[id] = nil; continue }
            running += 1
            Task {
                await run(track)
                running -= 1
                pump()
            }
        }
    }

    private func run(_ track: Track) async {
        guard NetworkMonitor.shared.isOnline else { states[track.id] = .failed("Offline"); return }
        states[track.id] = .downloading(0)
        let id = track.id
        let client = sources.client(for: track.sourceID)
        let rid = track.remoteID ?? ""
        do {
            let req = try await StreamLoader.shared.request(for: track, download: true)
            let url = try await StreamCache.download(req, id: id, to: Paths.downloads) { p in
                Task { @MainActor [weak self] in if case .downloading = self?.states[id] { self?.states[id] = .downloading(p) } }
            }
            StreamCache.remove(id)
            let rel = Paths.relative(url)
            library.keep([id])
            library.update(id) { $0.path = rel }
            states[id] = nil
            // Keep lyrics offline too.
            if library.trackByID[id]?.lyrics == nil, let client, let lrc = await client.lyrics(remoteID: rid) {
                library.update(id) { $0.lyrics = lrc; $0.lyricsSource = "server" }
            }
        } catch {
            states[id] = .failed(error.localizedDescription)
        }
    }
}


// MARK: - Songs from modules

extension LibraryStore {
    /// The song for a module search result, if it was played or added before.
    func moduleTrack(_ m: ModuleTrack) -> Track? {
        track(source: "module:\(m.moduleID)", remoteID: m.trackID)
    }

    /// Returns the song for a module search result. Playing only remembers it (see `heard`);
    /// `keep: true` (Add to Library, Download…) puts it in the library.
    @discardableResult
    func addModuleTrack(_ m: ModuleTrack, keep: Bool = false) -> Track {
        if let existing = moduleTrack(m) {
            if keep { self.keep([existing.id]) }
            return trackByID[existing.id] ?? existing
        }
        var t = Track(title: m.title, artist: m.artist, album: m.album, duration: m.duration, path: "")
        t.sourceID = "module:\(m.moduleID)"
        t.remoteID = m.trackID
        t.artworkURL = m.cover
        if keep { upsert([t]) } else { addHeard(t) }
        Task { await ArtworkFetcher.shared.fetchModuleCovers(library: self) }
        return t
    }

    /// Same as `addModuleTrack` for a whole list, but changes the library once, so playing a search result with
    /// 30 neighbours doesn't rebuild the index and restart the cover download 30 times.
    func addModuleTracks(_ list: [ModuleTrack]) -> [Track] {
        var out: [Track] = []
        var fresh: [Track] = []
        var seen: [String: Track] = [:]
        for m in list {
            let key = "\(m.moduleID)|\(m.trackID)"
            if let t = seen[key] { out.append(t); continue }
            if let existing = moduleTrack(m) {
                seen[key] = existing; out.append(existing); continue
            }
            var t = Track(title: m.title, artist: m.artist, album: m.album, duration: m.duration, path: "")
            t.sourceID = "module:\(m.moduleID)"
            t.remoteID = m.trackID
            t.artworkURL = m.cover
            seen[key] = t; fresh.append(t); out.append(t)
        }
        if !fresh.isEmpty {
            addHeard(fresh)
            Task { await ArtworkFetcher.shared.fetchModuleCovers(library: self) }
        }
        return out
    }
}
