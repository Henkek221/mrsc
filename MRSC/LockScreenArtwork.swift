import AVFoundation
import CoreImage
import MediaPlayer
import UIKit

// MARK: - Style

nonisolated enum LockArtLayout: String, CaseIterable, Identifiable, Sendable {
    /// The cover fills the whole Lock Screen.
    case fill
    /// The cover sits on a blurred copy of itself, so nothing is cropped.
    case framed
    var id: String { rawValue }
    var title: String { self == .fill ? "Fill" : "Framed" }
}

nonisolated enum LockArtMotion: String, CaseIterable, Identifiable, Sendable {
    case still, breathe, drift
    var id: String { rawValue }
    var title: String {
        switch self {
        case .still: "Still"
        case .breathe: "Breathe"
        case .drift: "Drift"
        }
    }
    /// Length of one seamless loop.
    var loop: Double { self == .drift ? 20 : self == .breathe ? 12 : 2 }
    var fps: Int32 { self == .still ? 1 : 24 }
}

// MARK: - Now Playing artwork

/// Artwork for the system Now Playing (Lock Screen, Dynamic Island, Control Center, CarPlay).
/// Built once per song and style — handing the system a new object on every update makes it reload the image.
@MainActor
final class NowPlayingArtwork {
    static let shared = NowPlayingArtwork()

    private var squareKey = ""
    private var square: MPMediaItemArtwork?
    private var tallKey = ""
    private var tall: MPMediaItemAnimatedArtwork?

    static var supportsFullscreen: Bool {
        MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork)
    }

    func square(for t: Track) -> MPMediaItemArtwork? {
        let key = Self.key(t)
        if key != squareKey {
            squareKey = key
            square = Self.cover(t).map(Self.makeArtwork)
        }
        return square
    }

    /// The tall, full-screen Lock Screen artwork, rendered as a short looping video from the cover.
    func fullscreen(for t: Track, settings: AppSettings) -> MPMediaItemAnimatedArtwork? {
        guard settings.lockArtwork, Self.supportsFullscreen else { tallKey = ""; tall = nil; return nil }
        let style = LockArtStyle(layout: settings.lockArtLayout, motion: settings.lockArtMotion)
        let key = "\(Self.key(t))-\(style.id)"
        if key == tallKey { return tall }
        tallKey = key
        tall = Self.cover(t)?.cgImage.map { Self.makeAnimated(LockArtJob(key: key, cover: $0, style: style)) }
        return tall
    }

    private static func key(_ t: Track) -> String { "\(t.id.uuidString)-\(t.artVersion ?? 0)" }

    private static func cover(_ t: Track) -> UIImage? {
        ArtworkCache.image(for: t) ?? CoverKit.image(CoverKit.auto(t.album + t.artist), side: 1000)
    }

    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// Kept nonisolated: the system calls these handlers on its own queues.
    nonisolated private static func makeAnimated(_ job: LockArtJob) -> MPMediaItemAnimatedArtwork {
        MPMediaItemAnimatedArtwork(artworkID: job.key) { _, done in
            // Called exactly once, from any queue (see MPMediaItemAnimatedArtwork).
            nonisolated(unsafe) let done = done
            Task { done(await job.preview()) }
        } videoAssetFileURLRequestHandler: { _, done in
            nonisolated(unsafe) let done = done
            Task { done(await job.video()) }
        }
    }
}

// MARK: - Rendering

nonisolated struct LockArtStyle: Hashable, Sendable {
    var layout: LockArtLayout
    var motion: LockArtMotion
    var id: String { "\(layout.rawValue)-\(motion.rawValue)-v\(LockArtRenderer.version)" }
}

/// Renders the preview frame and the video lazily, once, off the main thread.
actor LockArtJob {
    nonisolated let key: String
    private let cover: CGImage
    private let style: LockArtStyle
    private var renderer: LockArtRenderer?
    private var rendering: Task<URL?, Never>?

    init(key: String, cover: CGImage, style: LockArtStyle) {
        self.key = key
        self.cover = cover
        self.style = style
    }

    private func make() -> LockArtRenderer {
        if let renderer { return renderer }
        let r = LockArtRenderer(cover: cover, style: style)
        renderer = r
        return r
    }

    func preview() -> UIImage? { make().frame(at: 0).map(UIImage.init(cgImage:)) }

    func video() async -> URL? {
        if let rendering { return await rendering.value }
        guard let dir = LockArtRenderer.cacheDir else { return nil }
        let url = dir.appendingPathComponent("\(key).mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let r = make()
        let task = Task.detached(priority: .utility) { await r.writeVideo(to: url) ? url : nil }
        rendering = task
        return await task.value
    }
}

nonisolated struct LockArtRenderer: Sendable {
    static let width = 1080, height = 1440
    /// Bump when the drawing changes, so cached loops are rebuilt.
    static let version = 2

    let cover: CGImage
    let backdrop: CGImage?
    let style: LockArtStyle

    init(cover: CGImage, style: LockArtStyle) {
        self.cover = cover
        self.style = style
        backdrop = style.layout == .framed ? Self.blurred(cover) : nil
    }

    static var cacheDir: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("LockArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func frame(at t: Double) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Self.width, height: Self.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        draw(in: ctx, at: t)
        return ctx.makeImage()
    }

    private func draw(in ctx: CGContext, at t: Double) {
        let W = Double(Self.width), H = Double(Self.height)
        let p = t / style.motion.loop
        let wave = (1 - cos(2 * .pi * p)) / 2   // 0 → 1 → 0, loops cleanly
        ctx.interpolationQuality = .high
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        switch style.layout {
        case .fill:
            var zoom = 1.0, panX = 0.0, panY = 0.0
            switch style.motion {
            case .still: break
            case .breathe: zoom = 1 + 0.08 * wave
            case .drift: zoom = 1.06; panX = sin(2 * .pi * p); panY = 0.6 * cos(2 * .pi * p)
            }
            drawFilled(cover, in: ctx, zoom: zoom, panX: panX, panY: panY)
        case .framed:
            if let backdrop {
                let drifting = style.motion == .drift
                drawFilled(backdrop, in: ctx, zoom: drifting ? 1.12 : 1.04,
                           panX: drifting ? sin(2 * .pi * p) : 0, panY: drifting ? 0.6 * cos(2 * .pi * p) : 0)
            }
            let side = W * 0.74 * (style.motion == .breathe ? 1 + 0.04 * wave : 1)
            let rect = CGRect(x: (W - side) / 2, y: H * 0.54 - side / 2, width: side, height: side)
            let path = CGPath(roundedRect: rect, cornerWidth: side * 0.05, cornerHeight: side * 0.05, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: UIColor.black.withAlphaComponent(0.55).cgColor)
            ctx.addPath(path)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.draw(cover, in: rect)
            ctx.restoreGState()
        }
    }

    /// Aspect-fills the frame; `panX`/`panY` (-1…1) move across whatever overflows.
    private func drawFilled(_ image: CGImage, in ctx: CGContext, zoom: Double, panX: Double, panY: Double) {
        let W = Double(Self.width), H = Double(Self.height)
        let iw = Double(image.width), ih = Double(image.height)
        let s = max(W / iw, H / ih) * zoom
        let dw = iw * s, dh = ih * s
        let x = (W - dw) / 2 + panX * (dw - W) / 2
        let y = (H - dh) / 2 + panY * (dh - H) / 2
        ctx.draw(image, in: CGRect(x: x, y: y, width: dw, height: dh))
    }

    private static func blurred(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(image.width) * 0.04)
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.18, kCIInputSaturationKey: 1.2])
            .cropped(to: input.extent)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: input.extent)
    }

    func writeVideo(to url: URL) async -> Bool {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp4")
        guard let writer = try? AVAssetWriter(outputURL: tmp, fileType: .mp4) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Self.width,
            AVVideoHeightKey: Self.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_500_000]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height
        ])
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        let fps = style.motion.fps
        let count = Int(style.motion.loop * Double(fps))
        for i in 0..<count {
            while !input.isReadyForMoreMediaData { try? await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Self.width, height: Self.height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                draw(in: ctx, at: Double(i) / Double(fps))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: fps))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: Int64(count), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else { try? FileManager.default.removeItem(at: tmp); return false }

        let fm = FileManager.default
        try? fm.removeItem(at: url)
        guard (try? fm.moveItem(at: tmp, to: url)) != nil else { return false }
        // Keep only the newest few loops.
        let dir = url.deletingLastPathComponent()
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let old = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }.dropFirst(6)
        for f in old { try? fm.removeItem(at: f) }
        return true
    }
}
