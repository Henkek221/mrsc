import Foundation
import MusicKit
import SwiftUI

// MARK: - Recognising a shared playlist link

/// A playlist (or album) link from another streaming app, pasted or shared into the song-list import.
nonisolated struct PlaylistLink: Hashable, Sendable {
    enum Service: String, Sendable {
        case spotify, appleMusic, youTube, deezer

        var name: String {
            switch self {
            case .spotify: "Spotify"
            case .appleMusic: "Apple Music"
            case .youTube: "YouTube Music"
            case .deezer: "Deezer"
            }
        }
    }
    enum Kind: String, Sendable { case playlist, album }

    let service: Service
    let kind: Kind
    let id: String
    /// Apple Music only: the country the link was shared from.
    var storefront: String?

    var label: String { "\(service.name) \(kind == .album ? "album" : "playlist")" }

    /// The first supported link in some text ("Check this out: https://open.spotify.com/playlist/…?si=…").
    static func detect(in text: String) -> PlaylistLink? {
        for word in text.split(whereSeparator: { $0.isWhitespace || $0 == "\"" || $0 == "<" || $0 == ">" }) {
            if let u = URL(string: String(word)), let link = from(u) { return link }
        }
        return nil
    }

    /// True for short links (spotify.link, deezer.page.link, …) that only lead to a playlist after a redirect.
    static func isShortLink(_ text: String) -> URL? {
        for word in text.split(whereSeparator: \.isWhitespace) {
            guard let u = URL(string: String(word)), let host = u.host()?.lowercased() else { continue }
            if ["spotify.link", "spotify.app.link", "deezer.page.link", "link.deezer.com", "dzr.page.link"].contains(host) { return u }
        }
        return nil
    }

    static func from(_ url: URL) -> PlaylistLink? {
        guard let host = url.host()?.lowercased() else {
            // spotify:playlist:<id>
            let parts = url.absoluteString.split(separator: ":")
            if parts.count == 3, parts[0] == "spotify", let k = Kind(rawValue: String(parts[1])) {
                return PlaylistLink(service: .spotify, kind: k, id: String(parts[2]))
            }
            return nil
        }
        let path = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if host == "open.spotify.com" || host == "play.spotify.com" {
            // /playlist/<id>, /intl-de/playlist/<id>, /embed/playlist/<id>, /user/<u>/playlist/<id>
            for (i, p) in path.enumerated() where i + 1 < path.count {
                if let k = Kind(rawValue: p) { return PlaylistLink(service: .spotify, kind: k, id: path[i + 1]) }
            }
        }
        if host == "music.apple.com" || host == "itunes.apple.com" || host == "geo.music.apple.com" {
            // /us/playlist/<slug>/pl.xxx, /us/album/<slug>/1234
            if let i = path.firstIndex(where: { $0 == "playlist" || $0 == "album" }), let last = path.last, last != path[i] {
                let storefront = i > 0 && path[i - 1].count == 2 ? path[i - 1] : nil
                return PlaylistLink(service: .appleMusic, kind: path[i] == "album" ? .album : .playlist, id: last, storefront: storefront)
            }
        }
        if host.hasSuffix("youtube.com") || host == "youtu.be" {
            if let list = query.first(where: { $0.name == "list" })?.value, !list.isEmpty {
                return PlaylistLink(service: .youTube, kind: .playlist, id: list)
            }
        }
        if host.hasSuffix("deezer.com") {
            for (i, p) in path.enumerated() where i + 1 < path.count {
                if let k = Kind(rawValue: p), path[i + 1].allSatisfy(\.isNumber) { return PlaylistLink(service: .deezer, kind: k, id: path[i + 1]) }
            }
        }
        return nil
    }
}

nonisolated struct FetchedPlaylist: Sendable {
    struct Song: Sendable { let title: String; let artist: String }
    var name: String
    var songs: [Song]
    /// Shown above the results, e.g. when a service only hands out the first 100 songs.
    var note: String?

    /// The song list in the "Artist - Title" form the matcher reads.
    var lines: [String] { songs.map { $0.artist.isEmpty ? $0.title : "\($0.artist) - \($0.title)" } }
}

nonisolated enum PlaylistFetchError: LocalizedError {
    case notFound(PlaylistLink.Service)
    case noMusicAccess
    case unreadable(PlaylistLink.Service)
    case empty

    var errorDescription: String? {
        switch self {
        case .notFound(let s): "This \(s.name) playlist couldn't be opened. It may be private: make it public in \(s.name) (or copy the songs as text) and try again."
        case .noMusicAccess: "MRSC needs access to Apple Music to read Apple Music playlists. You can allow it in Settings ▸ Apps ▸ MRSC."
        case .unreadable(let s): "\(s.name) didn't send the song list in a form MRSC understands. Try again later, or copy the songs as text."
        case .empty: "This playlist has no songs."
        }
    }
}

// MARK: - Fetching

/// Reads the song list behind a playlist link. Nothing here signs in or ships a key: Spotify and YouTube are read
/// from their public pages, Deezer from its open API, Apple Music through MusicKit with the user's OK.
nonisolated enum PlaylistLinkFetcher {
    /// Hard stop for huge playlists, so a 10,000-song list doesn't stall the import.
    static let maxSongs = 2_000
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Follows a short link (spotify.link, deezer.page.link) to the playlist it points at.
    @concurrent
    static func resolve(_ url: URL) async -> PlaylistLink? {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return nil }
        if let final = response.url, let link = PlaylistLink.from(final) { return link }
        // Some short links answer with a page that redirects in script; the target URL is in it.
        let body = String(decoding: data, as: UTF8.self)
        for pattern in [#"https://open\.spotify\.com/[^"'\s<>\\]+"#, #"https://www\.deezer\.com/[^"'\s<>\\]+"#] {
            if let r = body.range(of: pattern, options: .regularExpression), let u = URL(string: String(body[r])), let link = PlaylistLink.from(u) {
                return link
            }
        }
        return nil
    }

    @concurrent
    static func fetch(_ link: PlaylistLink) async throws -> FetchedPlaylist {
        var result: FetchedPlaylist
        switch link.service {
        case .spotify: result = try await spotify(link)
        case .appleMusic: result = try await appleMusic(link)
        case .youTube: result = try await youTube(link)
        case .deezer: result = try await deezer(link)
        }
        if result.songs.isEmpty { throw PlaylistFetchError.empty }
        if result.songs.count > maxSongs {
            result.songs = Array(result.songs.prefix(maxSongs))
            result.note = "Only the first \(maxSongs) songs were imported."
        }
        return result
    }

    private static func page(_ url: URL, cookie: String? = nil) async throws -> (String, Int) {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("en", forHTTPHeaderField: "Accept-Language")
        if let cookie { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await URLSession.shared.data(for: req)
        return (String(decoding: data, as: UTF8.self), (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func json(_ data: Data) -> Any? { try? JSONSerialization.jsonObject(with: data) }

    // MARK: Spotify

    /// The public embed player page carries the list as JSON (`__NEXT_DATA__`). It needs no login but only holds
    /// the first 100 songs; the full list needs a signed-in Web API app, which a public app can't ship.
    private static func spotify(_ link: PlaylistLink) async throws -> FetchedPlaylist {
        guard let url = URL(string: "https://open.spotify.com/embed/\(link.kind.rawValue)/\(link.id)") else { throw PlaylistFetchError.notFound(.spotify) }
        let (html, status) = try await page(url)
        guard status == 200 else { throw PlaylistFetchError.notFound(.spotify) }
        guard let start = html.range(of: #"<script id="__NEXT_DATA__" type="application/json">"#),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex),
              let root = json(Data(html[start.upperBound..<end.lowerBound].utf8)) as? [String: Any] else { throw PlaylistFetchError.unreadable(.spotify) }
        let state = ((root["props"] as? [String: Any])?["pageProps"] as? [String: Any])?["state"] as? [String: Any]
        guard let entity = (state?["data"] as? [String: Any])?["entity"] as? [String: Any] else { throw PlaylistFetchError.notFound(.spotify) }
        let list = entity["trackList"] as? [[String: Any]] ?? []
        let songs = list.compactMap { t -> FetchedPlaylist.Song? in
            guard let title = t["title"] as? String, !title.isEmpty else { return nil }
            // "Queen,\u{00A0}David Bowie": the first artist matches best against library tags.
            let artists = (t["subtitle"] as? String ?? "").replacingOccurrences(of: "\u{00A0}", with: " ")
            let first = artists.components(separatedBy: ", ").first ?? artists
            return .init(title: title, artist: first.trimmingCharacters(in: .whitespaces))
        }
        let name = entity["name"] as? String ?? entity["title"] as? String ?? "Spotify Playlist"
        let note = link.kind == .playlist && list.count >= 100
            ? "Spotify only shares the first 100 songs of a playlist without signing in. For longer playlists, export them as CSV (e.g. with Exportify) and paste the file's text."
            : nil
        return FetchedPlaylist(name: name, songs: songs, note: note)
    }

    // MARK: Apple Music

    /// Catalog playlists (editorial ones and shared user playlists, `pl.u-…`) through MusicKit, page by page.
    /// A playlist that's only in someone's library and was never shared can't be read.
    private static func appleMusic(_ link: PlaylistLink) async throws -> FetchedPlaylist {
        if MusicAuthorization.currentStatus == .notDetermined { _ = await MusicAuthorization.request() }
        guard MusicAuthorization.currentStatus == .authorized else { throw PlaylistFetchError.noMusicAccess }
        var storefront = link.storefront
        if storefront == nil { storefront = try? await MusicDataRequest.currentCountryCode }
        let sf = storefront ?? "us"
        let type = link.kind == .album ? "albums" : "playlists"

        func get(_ path: String) async throws -> [String: Any] {
            guard let url = URL(string: "https://api.music.apple.com\(path)") else { throw PlaylistFetchError.notFound(.appleMusic) }
            do {
                let data = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response().data
                return json(data) as? [String: Any] ?? [:]
            } catch {
                throw PlaylistFetchError.notFound(.appleMusic)
            }
        }

        let head = try await get("/v1/catalog/\(sf)/\(type)/\(link.id)")
        let name = (((head["data"] as? [[String: Any]])?.first?["attributes"] as? [String: Any])?["name"] as? String) ?? "Apple Music Playlist"
        var songs: [FetchedPlaylist.Song] = []
        var next: String? = "/v1/catalog/\(sf)/\(type)/\(link.id)/tracks?limit=100"
        while let path = next, songs.count < maxSongs {
            let page = try await get(path)
            for item in page["data"] as? [[String: Any]] ?? [] {
                guard let a = item["attributes"] as? [String: Any], let title = a["name"] as? String else { continue }
                songs.append(.init(title: title, artist: a["artistName"] as? String ?? ""))
            }
            next = page["next"] as? String
        }
        return FetchedPlaylist(name: name, songs: songs)
    }

    // MARK: Deezer

    /// Deezer's public API: no key, 100 songs per page with a `next` link. Private playlists answer with an error.
    private static func deezer(_ link: PlaylistLink) async throws -> FetchedPlaylist {
        func get(_ s: String) async throws -> [String: Any] {
            guard let url = URL(string: s) else { throw PlaylistFetchError.notFound(.deezer) }
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let obj = json(data) as? [String: Any] else { throw PlaylistFetchError.unreadable(.deezer) }
            if obj["error"] != nil { throw PlaylistFetchError.notFound(.deezer) }
            return obj
        }
        let base = "https://api.deezer.com/\(link.kind.rawValue)/\(link.id)"
        let head = try await get(base)
        let name = head["title"] as? String ?? "Deezer Playlist"
        var songs: [FetchedPlaylist.Song] = []
        var next: String? = base + "/tracks?limit=100&index=0"
        while let url = next, songs.count < maxSongs {
            let page = try await get(url)
            for t in page["data"] as? [[String: Any]] ?? [] {
                guard let title = t["title"] as? String else { continue }
                songs.append(.init(title: title, artist: (t["artist"] as? [String: Any])?["name"] as? String ?? ""))
            }
            next = page["next"] as? String
        }
        return FetchedPlaylist(name: name, songs: songs)
    }

    // MARK: YouTube Music

    /// The public playlist page (`ytInitialData`). Best effort: YouTube changes this page often, it lists the first
    /// 100 videos, and titles are video titles ("Artist - Song (Official Video)"), which the matcher cleans up.
    private static func youTube(_ link: PlaylistLink) async throws -> FetchedPlaylist {
        guard let url = URL(string: "https://www.youtube.com/playlist?list=\(link.id)&hl=en") else { throw PlaylistFetchError.notFound(.youTube) }
        // SOCS=CAI declines the EU consent screen (no personalisation cookies), so the page itself comes back.
        let (html, status) = try await page(url, cookie: "SOCS=CAI")
        guard status == 200 else { throw PlaylistFetchError.notFound(.youTube) }
        guard let start = html.range(of: "var ytInitialData = ") ?? html.range(of: "window[\"ytInitialData\"] = "),
              let end = html.range(of: ";</script>", range: start.upperBound..<html.endIndex),
              let root = json(Data(html[start.upperBound..<end.lowerBound].utf8)) else { throw PlaylistFetchError.unreadable(.youTube) }

        var songs: [FetchedPlaylist.Song] = []
        func text(_ v: Any?) -> String? {
            guard let d = v as? [String: Any] else { return nil }
            if let s = d["simpleText"] as? String { return s }
            return (d["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        }
        func walk(_ v: Any) {
            if let d = v as? [String: Any] {
                if let r = d["playlistVideoRenderer"] as? [String: Any] {
                    if let title = text(r["title"]), !title.isEmpty {
                        var channel = text(r["shortBylineText"]) ?? ""
                        channel = channel.replacingOccurrences(of: #"\s*-\s*Topic$|VEVO$"#, with: "", options: .regularExpression)
                        // "Artist - Song" titles carry their own artist; otherwise the channel is the artist.
                        songs.append(title.contains(" - ") ? .init(title: title, artist: "") : .init(title: title, artist: channel))
                    }
                    return
                }
                for x in d.values { walk(x) }
            } else if let a = v as? [Any] {
                for x in a { walk(x) }
            }
        }
        walk(root)
        guard !songs.isEmpty else {
            throw html.contains("playlistVideoListRenderer") ? PlaylistFetchError.unreadable(.youTube) : PlaylistFetchError.notFound(.youTube)
        }
        var name = "YouTube Playlist"
        if let r = html.range(of: #"<meta property="og:title" content="[^"]*""#, options: .regularExpression) {
            name = String(html[r]).replacingOccurrences(of: #"^<meta property="og:title" content=""#, with: "", options: .regularExpression)
                .dropLast().replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
        }
        let note = songs.count >= 100 ? "YouTube only shows the first 100 songs of a playlist on its public page." : nil
        return FetchedPlaylist(name: name, songs: songs, note: note)
    }
}

// MARK: - CSV exports (Exportify, TuneMyMusic, …)

nonisolated enum SongListCSV {
    /// "Track Name","Artist Name(s)",… exports turned into "Artist - Title" lines; nil when the text isn't such a CSV.
    static func lines(from text: String) -> [String]? {
        let rows = text.split(whereSeparator: \.isNewline).map { parse(String($0)) }
        guard let header = rows.first?.map({ $0.lowercased() }),
              let ti = header.firstIndex(where: { $0 == "track name" || $0 == "title" || $0 == "name" || $0 == "track" }),
              let ai = header.firstIndex(where: { $0.hasPrefix("artist") }) else { return nil }
        return rows.dropFirst().compactMap { r in
            guard ti < r.count, !r[ti].isEmpty else { return nil }
            let artist = ai < r.count ? (r[ai].components(separatedBy: CharacterSet(charactersIn: ",;")).first ?? r[ai]) : ""
            return artist.isEmpty ? r[ti] : "\(artist.trimmingCharacters(in: .whitespaces)) - \(r[ti])"
        }
    }

    private static func parse(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        var it = line.makeIterator()
        while let c = it.next() {
            if c == "\"" {
                if quoted, let n = it.next() {
                    if n == "\"" { cur.append("\"") } else { quoted = false; if n == "," { out.append(cur); cur = "" } else { cur.append(n) } }
                } else { quoted.toggle() }
            } else if c == "," && !quoted { out.append(cur); cur = "" }
            else { cur.append(c) }
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Hand-off from the Share Extension

/// The Share Extension drops the shared link into the App Group and opens `mrsc://import-playlist?url=…`.
/// The app picks it up from either path (the URL may not open if iOS blocks it), then opens the import sheet.
@Observable
final class PlaylistLinkInbox {
    static let shared = PlaylistLinkInbox()
    static let defaultsKey = "pendingPlaylistLink"

    /// Read once by the import sheet when it opens.
    var pending: String?

    /// Handles `mrsc://import-playlist?url=…`; false for any other URL.
    func handle(_ url: URL, router: Router) -> Bool {
        guard url.scheme == "mrsc", url.host() == "import-playlist" else { return false }
        let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
        AppGroup.defaults.removeObject(forKey: Self.defaultsKey)
        if let link { open(link, router: router) }
        return true
    }

    /// Called when the app becomes active: a link the extension saved but couldn't open the app for.
    func checkSaved(router: Router) {
        guard let link = AppGroup.defaults.string(forKey: Self.defaultsKey) else { return }
        AppGroup.defaults.removeObject(forKey: Self.defaultsKey)
        open(link, router: router)
    }

    private func open(_ link: String, router: Router) {
        pending = link
        if router.showSongListImport {
            // Already open: it picks the new link up through `pending`.
            return
        }
        router.startSongListImport()
    }
}

extension View {
    /// Opens the song-list import for links shared through the Share Extension.
    func playlistLinkHandoff(router: Router) -> some View {
        modifier(PlaylistLinkHandoff(router: router))
    }
}

private struct PlaylistLinkHandoff: ViewModifier {
    let router: Router
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { PlaylistLinkInbox.shared.checkSaved(router: router) }
        }
    }
}
