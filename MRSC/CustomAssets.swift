import SwiftUI
import CoreText
import Observation
import UniformTypeIdentifiers

// MARK: - Store

/// Fonts and icons you bring yourself. Kept in Application Support and registered for this app only on launch.
@Observable
final class CustomAssets {
    static let shared = CustomAssets()

    struct Face: Hashable {
        let postScript: String
        let weight: CGFloat
        let italic: Bool
    }
    struct CustomFont: Identifiable, Hashable {
        let family: String
        var faces: [Face]
        var files: [String]
        var id: String { family }
    }

    private(set) var fonts: [CustomFont] = []
    /// Icon ids, newest first. Used in icon strings as `custom:<id>`.
    private(set) var icons: [String] = []

    @ObservationIgnored private var iconCache: [String: UIImage] = [:]

    static let iconPrefix = "custom:"
    private static let fontsDir = folder("Fonts")
    private static let iconsDir = folder("Icons")

    private static func folder(_ name: String) -> URL {
        let url = Paths.support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() {
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: Self.fontsDir, includingPropertiesForKeys: nil)) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        rebuildFonts()
        let files = (try? fm.contentsOfDirectory(at: Self.iconsDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        icons = files.filter { $0.pathExtension == "png" }
            .sorted { (Self.created($0) ?? .distantPast) > (Self.created($1) ?? .distantPast) }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    private static func created(_ url: URL) -> Date? { try? url.resourceValues(forKeys: [.creationDateKey]).creationDate }

    // MARK: Fonts

    /// The font of the theme on screen, if it's one of yours and still installed.
    var activeFont: CustomFont? { font(named: ThemeStore.shared.current.customFont) }

    func font(named family: String?) -> CustomFont? {
        guard let family else { return nil }
        return fonts.first { $0.family == family }
    }

    /// Copies font files in and registers them. Returns the families that were added.
    @discardableResult
    func importFonts(_ urls: [URL]) -> [String] {
        var added: [String] = []
        for src in urls {
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }
            guard let descs = CTFontManagerCreateFontDescriptorsFromURL(src as CFURL) as? [CTFontDescriptor], !descs.isEmpty else { continue }
            let dest = Self.fontsDir.appendingPathComponent(src.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                CTFontManagerUnregisterFontsForURL(dest as CFURL, .process, nil)
                try? FileManager.default.removeItem(at: dest)
            }
            guard (try? FileManager.default.copyItem(at: src, to: dest)) != nil else { continue }
            CTFontManagerRegisterFontsForURL(dest as CFURL, .process, nil)
            added += descs.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
        }
        rebuildFonts()
        return Array(Set(added)).sorted()
    }

    func delete(_ font: CustomFont) {
        for file in font.files {
            let url = Self.fontsDir.appendingPathComponent(file)
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
            try? FileManager.default.removeItem(at: url)
        }
        rebuildFonts()
    }

    private func rebuildFonts() {
        var byFamily: [String: CustomFont] = [:]
        for url in (try? FileManager.default.contentsOfDirectory(at: Self.fontsDir, includingPropertiesForKeys: nil)) ?? [] {
            for d in (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? [] {
                guard let family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String,
                      let ps = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String else { continue }
                let traits = CTFontDescriptorCopyAttribute(d, kCTFontTraitsAttribute) as? [CFString: Any]
                let weight = (traits?[kCTFontWeightTrait] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
                let symbolic = (traits?[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
                let face = Face(postScript: ps, weight: weight, italic: symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0)
                var f = byFamily[family] ?? CustomFont(family: family, faces: [], files: [])
                if !f.faces.contains(face) { f.faces.append(face) }
                if !f.files.contains(url.lastPathComponent) { f.files.append(url.lastPathComponent) }
                byFamily[family] = f
            }
        }
        fonts = byFamily.values.sorted { $0.family.localizedCaseInsensitiveCompare($1.family) == .orderedAscending }
    }

    // MARK: Icons

    static func isCustomIcon(_ name: String) -> Bool { name.hasPrefix(iconPrefix) }

    /// Imports pictures as tab icons: fitted into a square, dark-on-light pictures turned into a cut-out.
    @discardableResult
    func importIcons(_ urls: [URL]) -> [String] {
        var added: [String] = []
        for src in urls {
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: src), let image = UIImage(data: data),
                  let png = Self.iconPNG(from: image) else { continue }
            let id = UUID().uuidString
            guard (try? png.write(to: Self.iconsDir.appendingPathComponent("\(id).png"), options: .atomic)) != nil else { continue }
            added.append(id)
        }
        icons.insert(contentsOf: added.reversed(), at: 0)
        return added
    }

    func deleteIcon(_ id: String) {
        try? FileManager.default.removeItem(at: Self.iconsDir.appendingPathComponent("\(id).png"))
        iconCache[id] = nil
        icons.removeAll { $0 == id }
    }

    /// A 25 pt template image (the tab bar's icon size), or nil when the icon isn't on this device.
    func iconImage(_ name: String) -> UIImage? {
        guard Self.isCustomIcon(name) else { return nil }
        let id = String(name.dropFirst(Self.iconPrefix.count))
        _ = icons // follow imports and deletions
        if let hit = iconCache[id] { return hit }
        guard let data = try? Data(contentsOf: Self.iconsDir.appendingPathComponent("\(id).png")),
              let img = UIImage(data: data, scale: Self.iconPixels / 25) else { return nil }
        let template = img.withRenderingMode(.alwaysTemplate)
        iconCache[id] = template
        return template
    }

    private static let iconPixels: CGFloat = 150

    private static func iconPNG(from image: UIImage) -> Data? {
        let side = iconPixels
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let fit = min(side / size.width, side / size.height)
        let rect = CGRect(x: (side - size.width * fit) / 2, y: (side - size.height * fit) / 2, width: size.width * fit, height: size.height * fit)
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in image.draw(in: rect) }
        guard let cg = drawn.cgImage else { return nil }
        return (isCutOut(cg, inside: rect) ? drawn : luminanceMask(cg)).pngData()
    }

    private static func pixels(_ cg: CGImage) -> (data: [UInt8], w: Int, h: Int)? {
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    /// See-through pixels inside the picture itself (not the margin around a non-square one) mean it's already a cut-out.
    private static func isCutOut(_ cg: CGImage, inside rect: CGRect) -> Bool {
        guard let (data, w, _) = pixels(cg) else { return true }
        let r = rect.insetBy(dx: 1, dy: 1).integral
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) where data[(y * w + x) * 4 + 3] < 250 { return true }
        }
        return false
    }

    /// Dark strokes on a light background become the icon; the background drops out.
    private static func luminanceMask(_ cg: CGImage) -> UIImage {
        guard var (data, w, h) = pixels(cg) else { return UIImage(cgImage: cg) }
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let a = Double(data[i + 3]) / 255
            guard a > 0 else { continue }
            let lum = (0.299 * Double(data[i]) + 0.587 * Double(data[i + 1]) + 0.114 * Double(data[i + 2])) / 255 / a
            let ink = UInt8(max(0, min(1, (1 - lum) * a)) * 255)
            data[i] = 0; data[i + 1] = 0; data[i + 2] = 0; data[i + 3] = ink
        }
        let out = data.withUnsafeMutableBytes { buf -> CGImage? in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        return out.map { UIImage(cgImage: $0) } ?? UIImage(cgImage: cg)
    }

    // MARK: Bars

    /// Navigation bar titles are UIKit; they pick the font up when the next bar is made.
    func applyBarFonts(_ family: String?) {
        let bar = UINavigationBar.appearance()
        guard let f = font(named: family) else {
            bar.titleTextAttributes = nil
            bar.largeTitleTextAttributes = nil
            return
        }
        bar.titleTextAttributes = f.uiFont(size: 17, weight: .semibold).map { [.font: $0] }
        bar.largeTitleTextAttributes = f.uiFont(size: 34, weight: .bold).map { [.font: $0] }
    }
}

// MARK: - Picking faces

extension CustomAssets.CustomFont {
    /// The upright face closest to a weight (UIFont.Weight scale, -1…1).
    func face(for weight: CGFloat) -> CustomAssets.Face? {
        let upright = faces.filter { !$0.italic }
        return (upright.isEmpty ? faces : upright).min { abs($0.weight - weight) < abs($1.weight - weight) }
    }

    func font(size: CGFloat, weight: Font.Weight?, relativeTo style: Font.TextStyle? = nil) -> Font {
        let w = weight.map(Font.Weight.value) ?? 0
        guard let face = face(for: w) else { return .system(size: size, weight: weight) }
        let base: Font = style.map { Font.custom(face.postScript, size: size, relativeTo: $0) } ?? Font.custom(face.postScript, fixedSize: size)
        // A single face (often a variable font) can't be swapped, so ask it for the weight instead.
        return faces.count == 1 && weight != nil ? base.weight(weight!) : base
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight) -> UIFont? {
        face(for: weight.rawValue).flatMap { UIFont(name: $0.postScript, size: size) }
    }
}

extension Font.Weight {
    static func value(_ w: Font.Weight) -> CGFloat {
        switch w {
        case .ultraLight: UIFont.Weight.ultraLight.rawValue
        case .thin: UIFont.Weight.thin.rawValue
        case .light: UIFont.Weight.light.rawValue
        case .medium: UIFont.Weight.medium.rawValue
        case .semibold: UIFont.Weight.semibold.rawValue
        case .bold: UIFont.Weight.bold.rawValue
        case .heavy: UIFont.Weight.heavy.rawValue
        case .black: UIFont.Weight.black.rawValue
        default: 0
        }
    }
}

// MARK: - Theme-aware fonts

extension Font {
    /// `Font.system(size:)` in the theme's own font when it brings one. An explicit design (monospaced
    /// numbers, code) stays system. Pass `theme` to draw a theme other than the current one (previews).
    static func app(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil, theme: AppTheme? = nil) -> Font {
        let custom = theme.map { CustomAssets.shared.font(named: $0.customFont) } ?? CustomAssets.shared.activeFont
        guard design == nil, let custom else { return .system(size: size, weight: weight, design: design) }
        return custom.font(size: size, weight: weight)
    }

    /// A text style (`.caption`, `.headline` …) in the theme's font, still following Dynamic Type.
    static func app(_ style: Font.TextStyle) -> Font {
        guard let custom = CustomAssets.shared.activeFont else { return .system(style) }
        return custom.font(size: style.pointSize, weight: style == .headline ? .semibold : nil, relativeTo: style)
    }
}

extension Font.TextStyle {
    /// Sizes at the default text size; `relativeTo:` scales them from there.
    var pointSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

// MARK: - Icons in views

/// An SF Symbol, or one of your imported icons (`custom:<id>`), with a fallback symbol when that icon isn't here.
struct IconImage: View {
    let name: String
    var fallback = "questionmark.square.dashed"
    /// Size of an imported icon; symbols follow the font as usual.
    var size: CGFloat = 22

    var body: some View {
        if CustomAssets.isCustomIcon(name) {
            if let img = CustomAssets.shared.iconImage(name) {
                Image(uiImage: img).resizable().scaledToFit().frame(width: size, height: size)
            } else {
                Image(systemName: fallback)
            }
        } else {
            Image(systemName: name)
        }
    }
}

extension Image {
    /// For places that need a plain `Image` (tab bar items): the icon at its 25 pt size.
    static func icon(_ name: String, fallback: String = "questionmark.square.dashed") -> Image {
        if CustomAssets.isCustomIcon(name) {
            return CustomAssets.shared.iconImage(name).map { Image(uiImage: $0) } ?? Image(systemName: fallback)
        }
        return Image(systemName: name)
    }
}

// MARK: - Pickers

/// The theme's font: the built-in styles plus every font you've imported.
struct FontPicker: View {
    @Binding var theme: AppTheme
    @State private var assets = CustomAssets.shared
    @State private var importing: CustomAssetsView.Kind?

    var body: some View {
        List {
            Section("Built In") {
                ForEach(AppTheme.FontStyle.allCases) { style in
                    row(style.title, font: .system(size: 19, design: style.design), on: theme.customFont == nil && theme.font == style) {
                        theme.font = style; theme.customFont = nil
                    }
                }
            }
            Section {
                ForEach(assets.fonts) { f in
                    row(f.family, font: f.font(size: 19, weight: nil), on: theme.customFont == f.family) { theme.customFont = f.family }
                }
                if let missing = theme.customFont, assets.font(named: missing) == nil {
                    Label("\(missing) isn't on this iPhone. Import it to use it; until then the theme uses \(theme.font.title).", systemImage: "exclamationmark.triangle")
                        .font(.app(.footnote)).foregroundStyle(.secondary)
                }
                Button { importing = .font } label: { Label("Import Font…", systemImage: "plus") }
            } header: { Text("Your Fonts") } footer: {
                Text("TTF, OTF or TTC files from Files. Delete them under Customize → Fonts & Icons.")
            }
        }
        .navigationTitle("Font")
        .navigationBarTitleDisplayMode(.inline)
        .assetImporter($importing)
    }

    private func row(_ title: String, font: Font, on: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack {
                Text(title).font(font).foregroundStyle(.primary)
                Spacer()
                if on { Image(systemName: "checkmark").font(.app(.body).bold()).foregroundStyle(Theme.accent) }
            }
        }
    }
}

/// Your imported icons as a grid of choices, with an import button.
struct CustomIconGrid: View {
    @Binding var selection: String
    @State private var assets = CustomAssets.shared
    @State private var importing: CustomAssetsView.Kind?

    var body: some View {
        if !assets.icons.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                ForEach(assets.icons, id: \.self) { id in
                    let name = CustomAssets.iconPrefix + id
                    Button { selection = name } label: {
                        IconImage(name: name)
                            .frame(width: 44, height: 44)
                            .background(selection == name ? Theme.accent.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(selection == name ? Theme.accent : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
        Button { importing = .icon } label: { Label("Import Icons…", systemImage: "photo.badge.plus") }
            .assetImporter($importing) { added in
                if added > 0, let newest = assets.icons.first { selection = CustomAssets.iconPrefix + newest }
            }
    }
}

// MARK: - Manage

struct CustomAssetsView: View {
    @State private var assets = CustomAssets.shared
    @State private var importing: Kind?
    @State private var message: String?

    enum Kind: Identifiable { case font, icon; var id: Self { self } }

    var body: some View {
        List {
            Section {
                ForEach(assets.fonts) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(f.family).font(f.font(size: 20, weight: nil))
                        Text("\(f.faces.count) \(f.faces.count == 1 ? "style" : "styles")").font(.app(.caption)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { idx in idx.map { assets.fonts[$0] }.forEach(assets.delete) }
                Button { importing = .font } label: { Label("Import Font…", systemImage: "textformat") }
            } header: { Text("Fonts") } footer: {
                Text("TTF, OTF or TTC files. Pick one under Colors, Fonts, Player & Lyrics → Font. Shared themes keep the font's name; whoever opens one sees it if they've imported the same font.")
            }

            Section {
                if !assets.icons.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(assets.icons, id: \.self) { id in
                            IconImage(name: CustomAssets.iconPrefix + id)
                                .frame(width: 44, height: 44)
                                .contextMenu {
                                    Button(role: .destructive) { withAnimation { assets.deleteIcon(id) } } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Button { importing = .icon } label: { Label("Import Icons…", systemImage: "photo.badge.plus") }
            } header: { Text("Icons") } footer: {
                Text("PNGs with a transparent background work best; dark-on-white pictures are cut out automatically. Use them for tabs under Tab Bar. Touch and hold an icon to delete it.")
            }
        }
        .navigationTitle("Fonts & Icons")
        .navigationBarTitleDisplayMode(.inline)
        .assetImporter($importing) { added in
            if added == 0 { message = "Nothing could be imported. Fonts need to be TTF, OTF or TTC files; icons any picture." }
        }
        .alert("Import Failed", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
}

extension View {
    /// File picker for fonts or icons; `done` gets how many were added. Each file goes where its type says,
    /// so it doesn't matter which kind is cleared first when the picker closes.
    func assetImporter(_ kind: Binding<CustomAssetsView.Kind?>, done: @escaping (Int) -> Void = { _ in }) -> some View {
        fileImporter(isPresented: Binding(get: { kind.wrappedValue != nil }, set: { if !$0 { kind.wrappedValue = nil } }),
                     allowedContentTypes: kind.wrappedValue == .icon ? [.image] : [.font],
                     allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let isFont = { (u: URL) in UTType(filenameExtension: u.pathExtension)?.conforms(to: .font) == true }
            let fonts = CustomAssets.shared.importFonts(urls.filter(isFont))
            let icons = CustomAssets.shared.importIcons(urls.filter { !isFont($0) })
            done(fonts.count + icons.count)
        }
    }
}
