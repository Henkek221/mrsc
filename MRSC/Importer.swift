import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct ParsedMeta: Sendable {
    var title: String?
    var artist: String?
    /// Every credited artist when the tags name more than one (main artist first).
    var artists: [String]?
    var album: String?
    var trackNumber = 0
    var duration = 0.0
    var lyrics: String?
    var artwork: Data?
    var albumArtist: String?
    var genre: String?
    var year: Int?
    var discNumber: Int?
    var composer: String?
    var copyright: String?
    var bpm: Double?
    var replayGain: Double?
}

nonisolated enum Importer {
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "m4b", "alac", "mp4"]

    static func isAudio(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    static func audioFiles(in dir: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        while let obj = en.nextObject() {
            if let u = obj as? URL, isAudio(u) { out.append(u) }
        }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func subfolders(of dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    @concurrent
    static func readMetadata(_ url: URL) async -> ParsedMeta {
        let asset = AVURLAsset(url: url)
        var m = ParsedMeta()
        if let d = try? await asset.load(.duration), d.seconds.isFinite { m.duration = d.seconds }
        let items = (try? await asset.load(.metadata)) ?? []
        // Every artist value, not just the first: files can carry several artist tags (FLAC) or one tag with
        // several values. "ARTISTS" is the separate list some taggers write next to an "A feat. B" artist tag.
        var artistValues: [String] = []
        var listedArtists: [String] = []
        for item in items {
            guard let id = item.identifier else { continue }
            if id.rawValue.hasPrefix("vorb/") {
                await readVorbis(item, key: String(id.rawValue.dropFirst(5)).uppercased(), into: &m,
                                 artists: &artistValues, listed: &listedArtists)
                continue
            }
            switch id {
            case .commonIdentifierTitle, .iTunesMetadataSongName, .id3MetadataTitleDescription, .quickTimeMetadataTitle:
                guard m.title == nil else { continue }
                m.title = (try? await item.load(.stringValue)) ?? nil
            case .commonIdentifierArtist, .iTunesMetadataArtist, .id3MetadataLeadPerformer, .quickTimeMetadataArtist:
                if let v = (try? await item.load(.stringValue)) ?? nil { artistValues += v.components(separatedBy: "\0") }
            case .commonIdentifierAlbumName, .iTunesMetadataAlbum, .id3MetadataAlbumTitle, .quickTimeMetadataAlbum:
                guard m.album == nil else { continue }
                m.album = (try? await item.load(.stringValue)) ?? nil
            case .commonIdentifierArtwork, .iTunesMetadataCoverArt, .id3MetadataAttachedPicture, .quickTimeMetadataArtwork:
                guard m.artwork == nil else { continue }
                m.artwork = (try? await item.load(.dataValue)) ?? nil
            case .id3MetadataUnsynchronizedLyric, .iTunesMetadataLyrics:
                if m.lyrics == nil { m.lyrics = (try? await item.load(.stringValue)) ?? nil }
            case .id3MetadataTrackNumber:
                if let s = (try? await item.load(.stringValue)) ?? nil, let n = Int(s.split(separator: "/").first ?? "") { m.trackNumber = n }
            case .iTunesMetadataTrackNumber:
                if let d = (try? await item.load(.dataValue)) ?? nil, d.count >= 4 { m.trackNumber = Int(d[2]) << 8 | Int(d[3]) }
            case .iTunesMetadataAlbumArtist, .id3MetadataBand:
                if m.albumArtist == nil { m.albumArtist = (try? await item.load(.stringValue)) ?? nil }
            case .id3MetadataContentType, .iTunesMetadataUserGenre, .quickTimeMetadataGenre, .commonIdentifierType:
                if m.genre == nil, let g = (try? await item.load(.stringValue)) ?? nil { m.genre = cleanGenre(g) }
            case .id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate, .quickTimeMetadataYear, .commonIdentifierCreationDate, .id3MetadataReleaseTime:
                if m.year == nil, let v = (try? await item.load(.stringValue)) ?? nil, let y = Int(v.prefix(4)), y > 1000 { m.year = y }
            case .iTunesMetadataDiscNumber:
                if let d = (try? await item.load(.dataValue)) ?? nil, d.count >= 4 { m.discNumber = Int(d[2]) << 8 | Int(d[3]) }
            case .id3MetadataPartOfASet:
                if let v = (try? await item.load(.stringValue)) ?? nil { m.discNumber = Int(v.split(separator: "/").first ?? "") }
            case .iTunesMetadataComposer, .id3MetadataComposer, .quickTimeMetadataComposer:
                if m.composer == nil { m.composer = (try? await item.load(.stringValue)) ?? nil }
            case .commonIdentifierCopyrights, .id3MetadataCopyright, .iTunesMetadataCopyright, .quickTimeMetadataCopyright:
                if m.copyright == nil { m.copyright = (try? await item.load(.stringValue)) ?? nil }
            case .iTunesMetadataBeatsPerMin:
                if let n = (try? await item.load(.numberValue)) ?? nil { m.bpm = n.doubleValue }
                else if let d = (try? await item.load(.dataValue)) ?? nil, d.count >= 2 { m.bpm = Double(Int(d[d.count - 2]) << 8 | Int(d[d.count - 1])) }
            case .id3MetadataBeatsPerMinute:
                if let v = (try? await item.load(.stringValue)) ?? nil, let b = Double(v) { m.bpm = b }
            default:
                // ReplayGain and the artist list live in free-form tags (TXXX / iTunes "----").
                let raw = id.rawValue.lowercased()
                if raw.contains("replaygain_track_gain") || raw.contains("txxx") || raw.contains("----") {
                    let extra = (try? await item.load(.extraAttributes)) ?? nil
                    let desc = (extra?[.info] as? String ?? raw).lowercased()
                    if desc == "artists" || raw.hasSuffix(":artists"), let v = (try? await item.load(.stringValue)) ?? nil {
                        listedArtists += v.components(separatedBy: "\0")
                    }
                    if desc.contains("replaygain_track_gain") || raw.contains("replaygain_track_gain"),
                       let v = (try? await item.load(.stringValue)) ?? nil {
                        m.replayGain = Double(v.lowercased().replacingOccurrences(of: "db", with: "").trimmingCharacters(in: .whitespaces))
                    }
                }
            }
        }
        // AVFoundation keeps only the first value of a multi-value ID3v2.4 frame ("A\0B" → "A"), so read those frames directly.
        let id3 = ID3Artists.read(url)
        let credited = ArtistCredit.unique(id3.artists.count > 1 ? id3.artists : artistValues)
        let listed = ArtistCredit.unique(id3.listed.count > 1 ? id3.listed : listedArtists)
        if credited.count > 1 {
            m.artist = credited[0]
            m.artists = credited
        } else {
            // One artist tag ("A feat. B" or just "A"): keep it as written, with the separate list if there is one.
            m.artist = credited.first ?? listed.first
            if listed.count > 1 { m.artists = listed }
        }
        return m
    }

    /// FLAC and Ogg Vorbis comments. Each artist is often its own `ARTIST` entry.
    private static func readVorbis(_ item: AVMetadataItem, key: String, into m: inout ParsedMeta,
                                   artists: inout [String], listed: inout [String]) async {
        guard let v = ((try? await item.load(.stringValue)) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
        func number(_ s: String) -> Int? { Int(s.split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? "") }
        switch key {
        case "TITLE": if m.title == nil { m.title = v }
        case "ARTIST": artists.append(v)
        case "ARTISTS": listed.append(v)
        case "ALBUM": if m.album == nil { m.album = v }
        case "ALBUMARTIST", "ALBUM ARTIST": if m.albumArtist == nil { m.albumArtist = v }
        case "TRACKNUMBER": if m.trackNumber == 0, let n = number(v) { m.trackNumber = n }
        case "DISCNUMBER": if m.discNumber == nil { m.discNumber = number(v) }
        case "GENRE": if m.genre == nil { m.genre = cleanGenre(v) }
        case "DATE", "YEAR", "ORIGINALDATE": if m.year == nil, let y = Int(v.prefix(4)), y > 1000 { m.year = y }
        case "COMPOSER": if m.composer == nil { m.composer = v }
        case "COPYRIGHT": if m.copyright == nil { m.copyright = v }
        case "LYRICS", "UNSYNCEDLYRICS": if m.lyrics == nil { m.lyrics = v }
        case "BPM": if m.bpm == nil { m.bpm = Double(v) }
        case "REPLAYGAIN_TRACK_GAIN":
            m.replayGain = Double(v.lowercased().replacingOccurrences(of: "db", with: "").trimmingCharacters(in: .whitespaces))
        default: break
        }
    }

    /// ID3 genres can be "(17)" or "Rock"; "(17)Rock" style too.
    static func cleanGenre(_ g: String) -> String? {
        let names = ["Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal", "New Age", "Oldies",
                     "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial", "Alternative", "Ska", "Death Metal", "Pranks",
                     "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical", "Instrumental",
                     "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise", "Alternative Rock", "Bass", "Soul", "Punk", "Space", "Meditative",
                     "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic", "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk",
                     "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta", "Top 40", "Christian Rap", "Pop/Funk", "Jungle"]
        var t = g.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("("), let close = t.firstIndex(of: ")") {
            let num = Int(t[t.index(after: t.startIndex)..<close])
            let rest = t[t.index(after: close)...].trimmingCharacters(in: .whitespaces)
            t = rest.isEmpty ? num.flatMap { names.indices.contains($0) ? names[$0] : nil } ?? "" : rest
        } else if let n = Int(t), names.indices.contains(n) { t = names[n] }
        return t.isEmpty ? nil : t
    }

    @concurrent
    static func importFile(_ url: URL, artistFallback: String?, copy: Bool) async -> Track? {
        let fm = FileManager.default
        let id = UUID()
        var dest = url
        if copy {
            dest = Paths.imported.appendingPathComponent("\(id.uuidString).\(url.pathExtension.lowercased())")
            do { try fm.copyItem(at: url, to: dest) } catch { return nil }
        }
        let meta = await readMetadata(dest)
        var duration = meta.duration
        if duration <= 0, let f = try? AVAudioFile(forReading: dest) {
            duration = Double(f.length) / f.processingFormat.sampleRate
        }
        guard duration > 0 else {
            if copy { try? fm.removeItem(at: dest) }
            return nil
        }
        var lyrics = meta.lyrics
        if lyrics == nil {
            for ext in ["lrc", "txt"] {
                let side = url.deletingPathExtension().appendingPathExtension(ext)
                if let s = try? String(contentsOf: side, encoding: .utf8) { lyrics = s; break }
            }
        }
        var hasArt = false
        if let art = meta.artwork { hasArt = ArtworkWriter.writeJPEG(from: art, for: id) }
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty ?? true) ? nil : t
        }
        // No title tag: read what we can from the file name ("Title - Artist - Topic (192k)" and friends).
        let fileName = url.deletingPathExtension().lastPathComponent
        let fromName = clean(meta.title) == nil
            ? FileTitleParser.parse(fileName, artist: clean(meta.artist) ?? artistFallback ?? "Unknown Artist") : nil
        var track = Track(id: id,
                          title: clean(meta.title) ?? fromName?.title ?? fileName,
                          artist: clean(meta.artist) ?? fromName?.artist ?? artistFallback ?? "Unknown Artist",
                          album: clean(meta.album) ?? "Unknown Album",
                          duration: duration,
                          path: Paths.relative(dest),
                          trackNumber: meta.trackNumber > 0 ? meta.trackNumber : fromName?.number ?? 0,
                          lyrics: lyrics,
                          hasArtwork: hasArt)
        if hasArt { track.artSource = .file }
        track.applyExtendedTags(meta)
        return track
    }
}

// MARK: - Import flows

enum ImportKind: Identifiable {
    case audioFiles, playlistFolders, artistFolders, musicFolder
    var id: Self { self }
    var contentTypes: [UTType] { self == .audioFiles ? [.audio] : [.folder] }
}

extension LibraryStore {
    func handleImport(_ kind: ImportKind, urls: [URL]) async {
        switch kind {
        case .audioFiles: await importAudio(urls)
        case .playlistFolders: await importFolders(urls, asPlaylists: true)
        case .artistFolders: await importFolders(urls, asPlaylists: false)
        case .musicFolder:
            guard let folder = urls.first else { return }
            MusicFolder.set(folder)
            await scanChosenFolder()
        }
    }

    func importAudio(_ urls: [URL]) async {
        importStatus = ImportStatus(title: "Importing Music", done: 0, total: urls.count)
        var added: [Track] = []
        for (i, url) in urls.enumerated() {
            let scoped = url.startAccessingSecurityScopedResource()
            if let t = await Importer.importFile(url, artistFallback: nil, copy: true) { added.append(t) }
            if scoped { url.stopAccessingSecurityScopedResource() }
            importStatus?.done = i + 1
        }
        merge(added)
        finishImport()
    }

    func importFolders(_ folders: [URL], asPlaylists: Bool) async {
        importStatus = ImportStatus(title: asPlaylists ? "Importing Playlists" : "Importing Artists", done: 0, total: 0)
        for folder in folders {
            let scoped = folder.startAccessingSecurityScopedResource()
            let subs = Importer.subfolders(of: folder)
            let groups: [(String, [URL])] = subs.isEmpty
                ? [(folder.lastPathComponent, Importer.audioFiles(in: folder))]
                : subs.map { ($0.lastPathComponent, Importer.audioFiles(in: $0)) }
            importStatus?.total += groups.reduce(0) { $0 + $1.1.count }
            for (name, files) in groups where !files.isEmpty {
                var imported: [Track] = []
                for url in files {
                    if let t = await Importer.importFile(url, artistFallback: asPlaylists ? nil : name, copy: true) { imported.append(t) }
                    importStatus?.done += 1
                }
                let ids = merge(imported)
                if asPlaylists { createPlaylist(name: name, trackIDs: ids) }
            }
            if scoped { folder.stopAccessingSecurityScopedResource() }
        }
        finishImport()
    }

    /// Imports every not-yet-imported audio file from the folder the user picked (remembered via a bookmark).
    func scanChosenFolder() async {
        guard let folder = MusicFolder.resolve() else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let known = Set(tracks.compactMap(\.sourceKey))
        let files = Importer.audioFiles(in: folder)
        func key(_ url: URL) -> String {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let rel = url.path.replacingOccurrences(of: folder.path, with: "")
            return "\(rel)|\(size)"
        }
        let fresh = files.filter { !known.contains(key($0)) }
        importStatus = ImportStatus(title: "Scanning “\(folder.lastPathComponent)”", done: 0, total: fresh.count)
        var added: [Track] = []
        for (i, url) in fresh.enumerated() {
            if var t = await Importer.importFile(url, artistFallback: nil, copy: true) {
                t.sourceKey = key(url)
                added.append(t)
            }
            importStatus?.done = i + 1
        }
        merge(added)
        finishImport()
    }

    func scanMusicFolder() async {
        let files = Importer.audioFiles(in: Paths.scanFolder)
        let known = Set(tracks.map(\.path))
        let fresh = files.filter { !known.contains(Paths.relative($0)) }
        importStatus = ImportStatus(title: "Scanning Music Folder", done: 0, total: fresh.count)
        var added: [Track] = []
        for (i, url) in fresh.enumerated() {
            if let t = await Importer.importFile(url, artistFallback: nil, copy: false) { added.append(t) }
            importStatus?.done = i + 1
        }
        let gone = tracks.filter { $0.path.hasPrefix("MRSCMusic/") && !FileManager.default.fileExists(atPath: Paths.url(for: $0).path) }
        if !gone.isEmpty { delete(Set(gone.map(\.id))) }
        merge(added)
        finishImport()
    }

    /// Re-reads tags of every track that has not been edited by hand.
    func fullScan() async {
        let targets = tracks.filter { !$0.metadataLocked && !$0.path.isEmpty }
        importStatus = ImportStatus(title: "Reading Metadata", done: 0, total: targets.count)
        var updated: [Track] = []
        for (i, old) in targets.enumerated() {
            let meta = await Importer.readMetadata(Paths.url(for: old))
            var t = old
            if let v = meta.title, !v.isEmpty { t.title = v }
            if let v = meta.artist, !v.isEmpty { t.artist = v }
            if let v = meta.album, !v.isEmpty { t.album = v }
            if meta.trackNumber > 0 { t.trackNumber = meta.trackNumber }
            if meta.duration > 0 { t.duration = meta.duration }
            if let v = meta.lyrics { t.lyrics = v }
            t.applyExtendedTags(meta)
            // Never put the file's cover back over one from Apple Music or one you chose.
            if let art = meta.artwork, !t.hasArtwork || (t.artSource ?? .file) == .file,
               ArtworkWriter.writeJPEG(from: art, for: t.id) {
                t.hasArtwork = true
                t.artSource = .file
                t.artVersion = (t.artVersion ?? 0) + 1
                ArtworkCache.evict(t.id)
            }
            updated.append(t)
            importStatus?.done = i + 1
        }
        replace(updated)
        finishImport()
    }

    func loadDemo() async {
        importStatus = ImportStatus(title: "Creating Demo Library", done: 0, total: 1)
        let demo = await DemoContent.generate()
        merge(demo)
        if playlists.isEmpty, !demo.isEmpty {
            let mix = createPlaylist(name: "Demo Mix", trackIDs: demo.shuffled().prefix(8).map(\.id))
            let focus = createPlaylist(name: "Late Night", trackIDs: demo.filter { $0.artist == "Neon Harbor" || $0.artist == "Lumen" }.map(\.id))
            pinned = [PinnedItem(kind: .playlist, key: mix.id.uuidString),
                      PinnedItem(kind: .album, key: "Aurora Vale|Northern Static"),
                      PinnedItem(kind: .artist, key: "Neon Harbor"),
                      PinnedItem(kind: .playlist, key: focus.id.uuidString),
                      PinnedItem(kind: .artist, key: "Lumen"),
                      PinnedItem(kind: .album, key: "Paper Tigers|Loud & Quiet")]
        }
        finishImport()
    }

    private func finishImport() {
        if let total = importStatus?.total { importStatus?.done = total }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.smooth) { importStatus = nil }
        }
    }
}


/// The user's own music folder, remembered with a security-scoped bookmark.
enum MusicFolder {
    private static let key = "musicFolderBookmark"
    private static let nameKey = "musicFolderName"

    static var name: String? { UserDefaults.standard.string(forKey: nameKey) }

    static func set(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
        }
    }

    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }
}


extension Track {
    nonisolated mutating func applyExtendedTags(_ m: ParsedMeta) {
        func clean(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty ?? true) ? nil : t
        }
        // A rescan with a single artist clears an old credit list.
        if clean(m.artist) != nil { artists = m.artists }
        if let v = clean(m.albumArtist) { albumArtist = v }
        if let v = clean(m.genre) { genre = v }
        if let v = m.year { year = v }
        if let v = m.discNumber, v > 0 { discNumber = v }
        if let v = clean(m.composer) { composer = v }
        if let v = clean(m.copyright) { copyright = v }
        if let v = m.bpm, v > 20 { bpm = v }
        if let v = m.replayGain { replayGain = v }
    }
}


/// Reads the artist frames of an ID3v2.3/2.4 tag with every value: `TPE1` and the `TXXX:ARTISTS` list.
nonisolated enum ID3Artists {
    static func read(_ url: URL) -> (artists: [String], listed: [String]) {
        guard let file = try? FileHandle(forReadingFrom: url) else { return ([], []) }
        defer { try? file.close() }
        guard let head = try? file.read(upToCount: 10), head.count == 10 else { return ([], []) }
        let h = [UInt8](head)
        guard h[0] == 0x49, h[1] == 0x44, h[2] == 0x33, h[3] == 3 || h[3] == 4 else { return ([], []) }
        let v4 = h[3] == 4, flags = h[5]
        let size = syncsafe(h[6...9])
        // Whole-tag unsynchronisation is rare and would need undoing first.
        guard flags & 0x80 == 0, size > 0, size < 64 << 20, let body = try? file.read(upToCount: size) else { return ([], []) }
        let tag = [UInt8](body)
        var pos = 0
        if flags & 0x40 != 0, tag.count >= 4 {
            pos = v4 ? syncsafe(tag[0...3]) : 4 + (Int(tag[0]) << 24 | Int(tag[1]) << 16 | Int(tag[2]) << 8 | Int(tag[3]))
        }
        var artists: [String] = [], listed: [String] = []
        while pos + 10 <= tag.count, tag[pos] != 0 {
            let id = String(decoding: tag[pos..<pos + 4], as: UTF8.self)
            let length = v4 ? syncsafe(tag[pos + 4...pos + 7])
                : Int(tag[pos + 4]) << 24 | Int(tag[pos + 5]) << 16 | Int(tag[pos + 6]) << 8 | Int(tag[pos + 7])
            let start = pos + 10, end = start + length
            guard length > 0, end <= tag.count else { break }
            // Skip compressed, encrypted or unsynchronised frames.
            if tag[pos + 9] == 0 {
                if id == "TPE1" { artists = texts(tag[start..<end]) }
                if id == "TXXX" {
                    let values = texts(tag[start..<end])
                    if values.first?.uppercased() == "ARTISTS" { listed = Array(values.dropFirst()) }
                }
            }
            pos = end
        }
        return (artists, listed)
    }

    private static func syncsafe(_ b: ArraySlice<UInt8>) -> Int {
        b.reduce(0) { $0 << 7 | Int($1 & 0x7f) }
    }

    /// The values of a text frame: an encoding byte, then strings separated by a (one or two byte) zero.
    private static func texts(_ frame: ArraySlice<UInt8>) -> [String] {
        guard let encoding = frame.first else { return [] }
        let bytes = Array(frame.dropFirst())
        let wide = encoding == 1 || encoding == 2
        var parts: [[UInt8]] = [], current: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if wide {
                guard i + 1 < bytes.count else { break }
                if bytes[i] == 0 && bytes[i + 1] == 0 { parts.append(current); current = [] } else { current += [bytes[i], bytes[i + 1]] }
                i += 2
            } else {
                if bytes[i] == 0 { parts.append(current); current = [] } else { current.append(bytes[i]) }
                i += 1
            }
        }
        parts.append(current)
        var littleEndian = true
        return parts.compactMap { raw -> String? in
            var raw = raw
            switch encoding {
            case 0: return String(bytes: raw, encoding: .isoLatin1)
            case 1:
                if raw.count >= 2, raw[0] == 0xFF, raw[1] == 0xFE { littleEndian = true; raw.removeFirst(2) }
                else if raw.count >= 2, raw[0] == 0xFE, raw[1] == 0xFF { littleEndian = false; raw.removeFirst(2) }
                return String(bytes: raw, encoding: littleEndian ? .utf16LittleEndian : .utf16BigEndian)
            case 2: return String(bytes: raw, encoding: .utf16BigEndian)
            default: return String(bytes: raw, encoding: .utf8)
            }
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
}
