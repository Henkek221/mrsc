import SwiftUI
import UIKit

// MARK: - Brand style (startup colour + matching app icon)

enum BrandStyle: String, CaseIterable, Identifiable {
    case red, orange, green, blue, violet, black
    var id: String { rawValue }

    static let key = "brandStyle"
    static var current: BrandStyle { BrandStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .red }

    var name: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .green: "Green"
        case .blue: "Blue"
        case .violet: "Violet"
        case .black: "OLED"
        }
    }
    var color: Color {
        switch self {
        case .red: Color(hex: "#FF3B5C")
        case .orange: Color(hex: "#FF7A1A")
        case .green: Color(hex: "#18B56A")
        case .blue: Color(hex: "#2F6BFF")
        case .violet: Color(hex: "#7C4DFF")
        case .black: Color.black
        }
    }
    /// nil is the primary icon (red).
    var iconName: String? { self == .red ? nil : "AppIcon-" + rawValue.capitalized }

    @MainActor func apply() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != iconName else { return }
        UIApplication.shared.setAlternateIconName(iconName)
    }
}

// MARK: - Hand-brushed wordmark

private enum SVGPath {
    /// Minimal parser for the M / L / Z commands the brushed letters use.
    nonisolated static func parse(_ d: String) -> Path {
        var tokens: [String] = []
        var number = ""
        func flush() { if !number.isEmpty { tokens.append(number); number = "" } }
        for ch in d {
            if "MLZ".contains(ch) { flush(); tokens.append(String(ch)) }
            else if ch == " " || ch == "," { flush() }
            else { number.append(ch) }
        }
        flush()
        var path = Path()
        var i = 0
        func pt() -> CGPoint { defer { i += 2 }; return CGPoint(x: Double(tokens[i]) ?? 0, y: Double(tokens[i + 1]) ?? 0) }
        while i < tokens.count {
            let c = tokens[i]; i += 1
            switch c {
            case "M": path.move(to: pt())
            case "L": path.addLine(to: pt())
            case "Z": path.closeSubpath()
            default: break
            }
        }
        return path
    }
}

/// One brushed letter, drawn in the 1024-point icon space and scaled to fit.
struct BrushLetter: Shape {
    let path: Path
    nonisolated func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / WordmarkData.size
        let ox = rect.minX + (rect.width - WordmarkData.size * s) / 2
        let oy = rect.minY + (rect.height - WordmarkData.size * s) / 2
        return path.applying(CGAffineTransform(scaleX: s, y: s).concatenating(CGAffineTransform(translationX: ox, y: oy)))
    }
    static let all: [BrushLetter] = WordmarkData.letters.map { BrushLetter(path: SVGPath.parse($0)) }
}

/// The app-icon logo (MR / SC). Each letter is stamped in on its own: it comes down big and slightly turned,
/// lands with a bounce, and a pale ring of ink jumps off the impact.
struct StampLogo: View {
    var ink: Color = .white
    /// One flag per letter; flipping to true plays that letter's stamp.
    var stamped: [Bool]

    private let tilt: [Double] = [-7, 6, 5, -6]

    var body: some View {
        ZStack {
            ForEach(0..<BrushLetter.all.count, id: \.self) { i in
                let on = stamped[safe: i] ?? false
                ZStack {
                    BrushLetter.all[i].fill(ink.opacity(on ? 0 : 0.5))
                        .scaleEffect(on ? 1.12 : 1)
                        .animation(.easeOut(duration: 0.35), value: on)
                    BrushLetter.all[i].fill(ink)
                }
                .scaleEffect(on ? 1 : 1.9, anchor: .center)
                .rotationEffect(.degrees(on ? 0 : tilt[i % tilt.count]))
                .opacity(on ? 1 : 0)
                .animation(.interpolatingSpring(stiffness: 520, damping: 22), value: on)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Startup splash

@MainActor @Observable
final class SplashState {
    static let shared = SplashState()
    static let enabledKey = "startupAnimation"
    var running: Bool

    private init() {
        let d = UserDefaults.standard
        running = d.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Onboarding and other covers wait until the splash is gone.
    func waitUntilDone() async {
        while running { try? await Task.sleep(for: .milliseconds(60)) }
    }
}

/// Stamps the four letters one after another with a haptic thump each. Shared by the splash and the settings preview.
@MainActor
func playStamps(_ stamped: Binding<[Bool]>, shake: Binding<CGSize>? = nil, haptics: Bool = true, gap: Int = 330) async {
    let thump = UIImpactFeedbackGenerator(style: .heavy)
    for i in 0..<stamped.wrappedValue.count {
        if Task.isCancelled { return }
        stamped[i].wrappedValue = true
        if haptics { thump.impactOccurred(intensity: 0.9) }
        if let shake {
            let dir: [CGSize] = [CGSize(width: -5, height: 4), CGSize(width: 5, height: 4), CGSize(width: -4, height: -3), CGSize(width: 4, height: -3)]
            shake.wrappedValue = dir[i % dir.count]
            try? await Task.sleep(for: .milliseconds(55))
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { shake.wrappedValue = .zero }
            try? await Task.sleep(for: .milliseconds(max(0, gap - 55)))
        } else {
            try? await Task.sleep(for: .milliseconds(gap))
        }
    }
}

struct LaunchSplash: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var filled = false
    @State private var stamped = [Bool](repeating: false, count: 4)
    @State private var shake = CGSize.zero
    @State private var leaving = false
    @State private var finished = false

    private let style = BrandStyle.current

    var body: some View {
        ZStack {
            // Starts in the system's launch colour so there is no flash, then the brand colour floods in.
            (scheme == .dark ? Color.black : Color.white)
            style.color.opacity(filled ? 1 : 0)
            StampLogo(stamped: stamped)
                .frame(maxWidth: 340)
                .padding(.horizontal, 30)
                .offset(shake)
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving ? 1.04 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
    }

    private func run() async {
        withAnimation(.easeOut(duration: 0.25)) { filled = true }
        if reduceMotion {
            stamped = stamped.map { _ in true }
            try? await Task.sleep(for: .milliseconds(700))
            finish(); return
        }
        try? await Task.sleep(for: .milliseconds(320))
        await playStamps($stamped, shake: $shake)
        try? await Task.sleep(for: .milliseconds(520))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.32)) { leaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(340))
            onFinish()
        }
    }
}

// MARK: - Settings

struct StartupSettingsView: View {
    @AppStorage(SplashState.enabledKey) private var enabled = true
    @AppStorage(BrandStyle.key) private var styleRaw = BrandStyle.red.rawValue
    @State private var stamped = [Bool](repeating: true, count: 4)
    @State private var shake = CGSize.zero
    @State private var playing: Task<Void, Never>?

    private var style: BrandStyle { BrandStyle(rawValue: styleRaw) ?? .red }

    var body: some View {
        List {
            Section {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(style.color)
                    StampLogo(stamped: stamped).padding(22).offset(shake)
                }
                .frame(height: 210)
                .animation(.easeInOut(duration: 0.25), value: styleRaw)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .onTapGesture { play() }
            }

            Section {
                Button { play() } label: { Label("Play Animation", systemImage: "play.fill") }
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                    ForEach(BrandStyle.allCases) { s in
                        Button {
                            styleRaw = s.rawValue
                            s.apply()
                            play()
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(s.color)
                                    .frame(height: 54)
                                    .overlay {
                                        // Pure black would vanish on a black background.
                                        if s == .black { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                                    }
                                    .overlay {
                                        if s == style { Image(systemName: "checkmark").font(.headline.bold()).foregroundStyle(.white) }
                                    }
                                Text(s.name).font(.caption).foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: { Text("Color") } footer: {
                Text("The startup animation and the app icon use the same color. iOS shows a short notice when the icon changes.")
            }

            Section {
                Toggle("Play on Launch", isOn: $enabled)
            }
        }
        .navigationTitle("Startup & App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func play() {
        playing?.cancel()
        stamped = stamped.map { _ in false }
        playing = Task {
            try? await Task.sleep(for: .milliseconds(250))
            await playStamps($stamped, shake: $shake, gap: 300)
        }
    }
}
