import Foundation

/// Synthesizes short instrumental demo tracks (WAV) with timed lyrics so the app is usable without importing anything.
nonisolated enum DemoContent {
    static let playlistNames: Set<String> = ["Demo Mix", "Late Night"]
    /// One demo song has no lyrics, so the visualizer shows up in the demo too.
    static let instrumental = "Chrome Rain"
    static let keys: Set<String> = Set(specs.map { "\($0.title)|\($0.artist)" })
    struct Spec {
        let title, artist, album: String
        let number: Int
        let bpm: Double
        let root: Int
        let minor: Bool
        let wave: Int
        let seconds: Double
    }

    static let specs: [Spec] = [
        .init(title: "Glass Horizon", artist: "Aurora Vale", album: "Northern Static", number: 1, bpm: 96, root: 57, minor: true, wave: 0, seconds: 42),
        .init(title: "Slow Signal", artist: "Aurora Vale", album: "Northern Static", number: 2, bpm: 84, root: 52, minor: true, wave: 1, seconds: 38),
        .init(title: "Paper Moons", artist: "Aurora Vale", album: "Northern Static", number: 3, bpm: 108, root: 60, minor: false, wave: 0, seconds: 40),
        .init(title: "Midnight Ferry", artist: "Neon Harbor", album: "After Hours City", number: 1, bpm: 118, root: 55, minor: true, wave: 2, seconds: 44),
        .init(title: "Chrome Rain", artist: "Neon Harbor", album: "After Hours City", number: 2, bpm: 124, root: 50, minor: true, wave: 2, seconds: 36),
        .init(title: "Last Train Home", artist: "Neon Harbor", album: "After Hours City", number: 3, bpm: 100, root: 57, minor: false, wave: 1, seconds: 41),
        .init(title: "Backyard Thunder", artist: "Paper Tigers", album: "Loud & Quiet", number: 1, bpm: 132, root: 52, minor: false, wave: 2, seconds: 37),
        .init(title: "Sunday Static", artist: "Paper Tigers", album: "Loud & Quiet", number: 2, bpm: 90, root: 55, minor: true, wave: 1, seconds: 39),
        .init(title: "Runaway Kite", artist: "Paper Tigers", album: "Loud & Quiet", number: 3, bpm: 112, root: 59, minor: false, wave: 0, seconds: 43),
        .init(title: "Golden Hour", artist: "Lumen", album: "Fields of Light", number: 1, bpm: 88, root: 60, minor: false, wave: 0, seconds: 45),
        .init(title: "Soft Echoes", artist: "Lumen", album: "Fields of Light", number: 2, bpm: 76, root: 53, minor: true, wave: 1, seconds: 40),
        .init(title: "Small Sun", artist: "Lumen", album: "Fields of Light", number: 3, bpm: 104, root: 62, minor: false, wave: 0, seconds: 36)
    ]

    private static let lyricPool = [
        "Lights are fading over the harbor",
        "I hear the static turning into song",
        "Hold on to the color of the evening",
        "We were never meant to stay this long",
        "Paper moons above the empty street",
        "Every signal finds a way back home",
        "Carry me through the quiet hours",
        "Where the river meets the neon glow",
        "Say it slow and let the echo answer",
        "Nothing lasts but the sound we made",
        "Chasing kites across the open field",
        "Tell me that the morning's on its way",
        "Small sun rising in my window",
        "Let the whole world fall away"
    ]

    @concurrent
    static func generate() async -> [Track] {
        var out: [Track] = []
        for (n, spec) in specs.enumerated() {
            let id = UUID()
            let samples = synth(spec, seed: UInt64(n * 7919 + 13))
            let url = Paths.imported.appendingPathComponent("\(id.uuidString).wav")
            guard (try? wav(samples, sampleRate: sampleRate).write(to: url)) != nil else { continue }
            out.append(Track(id: id, title: spec.title, artist: spec.artist, album: spec.album,
                             duration: spec.seconds, path: Paths.relative(url), trackNumber: spec.number,
                             lyrics: spec.title == instrumental ? nil : lyrics(for: spec, index: n), metadataLocked: true))
        }
        return out
    }

    private static func lyrics(for spec: Spec, index: Int) -> String {
        var lines: [String] = []
        var t = 3.0
        var k = index * 3
        while t < spec.seconds - 5 {
            let text = lyricPool[k % lyricPool.count]
            lines.append(String(format: "[%02d:%05.2f] %@", Int(t) / 60, t.truncatingRemainder(dividingBy: 60), text))
            t += 4.5
            k += 1
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Synth

    private static let sampleRate = 22_050.0

    private struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(1 << 31)
        }
    }

    private static func synth(_ spec: Spec, seed: UInt64) -> [Int16] {
        let count = Int(spec.seconds * sampleRate)
        var buf = [Float](repeating: 0, count: count)
        var rng = LCG(state: seed)
        let scale = spec.minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
        let step = 60.0 / spec.bpm / 2
        var degree = 2
        var t = 0.0
        var stepIndex = 0

        func add(midi: Int, at start: Double, length: Double, gain: Float, wave: Int, decay: Double) {
            let f = 440.0 * pow(2.0, Double(midi - 69) / 12)
            let first = Int(start * sampleRate)
            let n = Int((length + 0.4) * sampleRate)
            for i in 0..<n where first + i < count {
                let time = Double(i) / sampleRate
                let phase = 2 * Double.pi * f * time
                var s: Double
                switch wave {
                case 1: s = 2 / Double.pi * asin(sin(phase))
                case 2: s = sin(phase) + sin(phase * 3) / 3 + sin(phase * 5) / 5
                default: s = sin(phase) + 0.25 * sin(phase * 2)
                }
                let attack = min(1, time / 0.008)
                let env = attack * exp(-time * decay) * (time < length ? 1 : max(0, 1 - (time - length) / 0.4))
                buf[first + i] += Float(s * env) * gain
            }
        }

        while t < spec.seconds - 0.5 {
            if rng.next() < 0.82 {
                degree = max(0, min(13, degree + Int(rng.next() * 5) - 2))
                let midi = spec.root + 12 + scale[degree % 7] + 12 * (degree / 7)
                add(midi: midi, at: t, length: step * (rng.next() < 0.3 ? 2 : 1), gain: 0.16, wave: spec.wave, decay: 2.2)
            }
            if stepIndex % 4 == 0 {
                let bassDegree = [0, 3, 4, 2][(stepIndex / 4) % 4]
                add(midi: spec.root - 12 + scale[bassDegree % 7], at: t, length: step * 3.5, gain: 0.22, wave: 1, decay: 1.2)
            }
            if stepIndex % 2 == 0 { // soft tick
                let first = Int(t * sampleRate)
                for i in 0..<400 where first + i < count { buf[first + i] += Float(rng.next() - 0.5) * 0.05 * Float(exp(-Double(i) / 90)) }
            }
            t += step
            stepIndex += 1
        }

        let fade = Int(1.5 * sampleRate)
        var out = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            var v = buf[i]
            if i > count - fade { v *= Float(count - i) / Float(fade) }
            out[i] = Int16(max(-1, min(1, tanh(v * 1.4))) * 30_000)
        }
        return out
    }

    private static func wav(_ samples: [Int16], sampleRate: Double) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataSize = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataSize)
        samples.withUnsafeBufferPointer { d.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: samples.count * 2)) }
        return d
    }
}

extension Track {
    /// A song from the demo library (generated WAV with locked metadata).
    nonisolated var isDemo: Bool {
        metadataLocked == true && path.hasPrefix("Imported/") && path.hasSuffix(".wav")
            && DemoContent.keys.contains("\(title)|\(artist)")
    }
}
