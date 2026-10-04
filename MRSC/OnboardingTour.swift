import SwiftUI

// MARK: - See what it can do

/// "See what it can do": five calm pages in the website's look. One headline, one line, one thing to touch.
struct TourDeck: View {
    var onFinish: () -> Void
    @State private var page = 0

    private let pages = TourPage.allCases
    private var current: TourPage { TourPage(rawValue: page) ?? .themes }
    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            (current.onRed ? Theme.accent : Color(uiColor: .systemBackground))
                .ignoresSafeArea()
                .animation(.smooth(duration: 0.45), value: page)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { onFinish() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(current.onRed ? .white.opacity(0.8) : Site.ink2)
                        .opacity(isLast ? 0 : 1)
                }
                .padding(.horizontal, 20)
                .frame(height: 54)

                TabView(selection: $page) {
                    ForEach(pages) { p in
                        TourPageView(page: p, active: page == p.rawValue).tag(p.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                PageDots(count: pages.count, current: page, onRed: current.onRed)
                SitePill(isLast ? "Add my music" : "Next", onRed: current.onRed) {
                    if isLast { onFinish() }
                    else { withAnimation(.spring(duration: 0.5, bounce: 0.15)) { page += 1 } }
                }
                .padding(.top, 22)
                .padding(.bottom, 12)
            }
        }
        .sensoryFeedback(.selection, trigger: page)
    }
}

enum TourPage: Int, CaseIterable, Identifiable {
    case themes, lyrics, search, mix, leftOut
    var id: Int { rawValue }

    /// Only the last page is red, like the website's "Things we left out".
    var onRed: Bool { self == .leftOut }

    var title: String {
        switch self {
        case .themes: "Customize the shit out of it."
        case .lyrics: "Lyrics, even when there aren’t any."
        case .search: "Search like you talk."
        case .mix: "No gaps. No awkward silences."
        case .leftOut: ""
        }
    }

    var text: String {
        switch self {
        case .themes: "Tap a record. Colors, fonts and the player change with it."
        case .lyrics: "No lyrics in the file? MRSC listens and writes them, right on your iPhone."
        case .search: "“never played” or “favorites under 3 min”. It gets it. In German, too."
        case .mix: "Track Mix locks the next beat onto the end of the song."
        case .leftOut: ""
        }
    }
}

private struct TourPageView: View {
    let page: TourPage
    let active: Bool
    @State private var shown = false

    var body: some View {
        Group {
            if page == .leftOut {
                LeftOutPage(active: active)
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 14) {
                        headline
                        Text(page.text)
                            .siteLede(17)
                            .textRenderer(BlurReveal(progress: shown ? 1 : 0))
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
                    .padding(.top, 16)

                    Spacer(minLength: 24)
                    object
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 24)
                }
            }
        }
        .onChange(of: active, initial: true) { _, now in
            if now { withAnimation(.linear(duration: 0.8)) { shown = true } } else { shown = false }
        }
    }

    @ViewBuilder private var headline: some View {
        if page == .themes {
            Text("Customize the \(Text("shit").foregroundStyle(Theme.accent).customAttribute(Swear())) out of it.")
                .siteHeadline(36)
                .textRenderer(BrushUnderline(progress: shown ? 1 : 0, color: Theme.accent))
        } else {
            Text(page.title)
                .siteHeadline(36)
                .textRenderer(BlurReveal(progress: shown ? 1 : 0))
        }
    }

    @ViewBuilder private var object: some View {
        switch page {
        case .themes: ThemeCrate()
        case .lyrics: LyricsLines(active: active)
        case .search: SearchPill(active: active)
        case .mix: MixFader(active: active)
        case .leftOut: EmptyView()
        }
    }
}

/// The website's carousel dots: the current one stretches and turns red.
private struct PageDots: View {
    let count: Int
    let current: Int
    let onRed: Bool

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? (onRed ? Color.white : Theme.accent) : (onRed ? Color.white.opacity(0.4) : Color(uiColor: .systemGray4)))
                    .frame(width: i == current ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

// MARK: - Brush underline

/// Marks the word that gets the brush stroke.
private struct Swear: TextAttribute {}

/// Draws the text, then the website's red brush stroke under the word marked `Swear`.
private struct BrushUnderline: TextRenderer, Animatable {
    var progress: Double
    var color: Color

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                ctx.draw(run)
                guard run[Swear.self] != nil, progress > 0 else { continue }
                let b = run.typographicBounds
                let em = b.ascent + b.descent
                let x0 = b.rect.minX - b.rect.width * 0.02
                let w = b.rect.width * 1.04
                let top = b.origin.y + em * 0.02
                let h = em * 0.3
                // The website's path, M6 26 C120 12 300 38 474 18 in a 480×40 box.
                func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x0 + x / 480 * w, y: top + y / 40 * h) }
                var path = Path()
                path.move(to: p(6, 26))
                path.addCurve(to: p(474, 18), control1: p(120, 12), control2: p(300, 38))
                ctx.stroke(path.trimmedPath(from: 0, to: progress), with: .color(color.opacity(0.9)),
                           style: StrokeStyle(lineWidth: em * 0.085, lineCap: .round))
            }
        }
    }
}

// MARK: - 1 · Themes

/// Five themes as coloured pressings; the chosen one rises out of the crate and MRSC wears it.
private struct ThemeCrate: View {
    @State private var store = ThemeStore.shared

    private var themes: [AppTheme] {
        ["mrsc", "green-room", "crimson", "cloud", "pulse"].compactMap { id in AppTheme.builtIns.first { $0.id == id } }
    }

    var body: some View {
        let list = themes
        let selected = list.firstIndex { $0.id == store.selectedID } ?? 0
        VStack(spacing: 26) {
            ZStack {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                    // Neighbours sit on both sides of the chosen pressing, like a crate you flick through.
                    let n = list.count
                    let offset = ((i - selected + n + n / 2) % n) - n / 2
                    let on = offset == 0
                    Button { store.apply(t) } label: {
                        ColoredVinyl(color: t.accentColor, name: t.name)
                            .frame(width: 200, height: 200)
                    }
                    .buttonStyle(.plain)
                    .rotationEffect(.degrees(Double(offset) * 9))
                    .offset(x: CGFloat(offset) * 62, y: on ? -20 : 40 + CGFloat(abs(offset)) * 12)
                    .scaleEffect(on ? 1 : 0.8)
                    .shadow(color: .black.opacity(on ? 0.25 : 0.12), radius: on ? 26 : 10, y: on ? 20 : 6)
                    .zIndex(on ? 10 : Double(-abs(offset)))
                    .accessibilityLabel(t.name)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .frame(height: 270)

            Text(list[selected].name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Site.ink2)
                .contentTransition(.opacity)
        }
        .animation(.spring(duration: 0.55, bounce: 0.3), value: store.selectedID)
        .sensoryFeedback(.selection, trigger: store.selectedID)
    }
}

/// Translucent coloured vinyl with grooves, a fixed highlight and a paper label printed with its name.
private struct ColoredVinyl: View {
    let color: Color
    let name: String

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                Circle().fill(RadialGradient(colors: [color.mix(with: .white, by: 0.3), color, color.mix(with: .black, by: 0.45)],
                                             center: .center, startRadius: s * 0.1, endRadius: s * 0.5))
                ForEach(0..<12) { i in
                    Circle().strokeBorder(Color.white.opacity(0.06 + Double(i % 3) * 0.035), lineWidth: 0.8)
                        .padding(s * (0.04 + CGFloat(i) * 0.026))
                }
                Circle()
                    .fill(AngularGradient(stops: [
                        .init(color: .clear, location: 0), .init(color: .white.opacity(0.4), location: 0.1),
                        .init(color: .clear, location: 0.22), .init(color: .clear, location: 0.55),
                        .init(color: .white.opacity(0.22), location: 0.63), .init(color: .clear, location: 0.75),
                        .init(color: .clear, location: 1)
                    ], center: .center, angle: .degrees(-30)))
                    .blendMode(.plusLighter)
                Circle().fill(Color(white: 0.97)).frame(width: s * 0.34, height: s * 0.34)
                    .overlay {
                        VStack(spacing: s * 0.035) {
                            Text(name.uppercased())
                                .font(.system(size: s * 0.045, weight: .heavy))
                                .tracking(s * 0.004)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Circle().fill(color).frame(width: s * 0.03)
                            Text("MRSC").font(.system(size: s * 0.03, weight: .semibold)).opacity(0.5)
                        }
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: s * 0.28)
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 2 · Lyrics

/// One big line on white lighting up word by word in red, the next one waiting underneath.
private struct LyricsLines: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var lit = 0

    private static let lines = ["Lights are fading over the harbor", "I hear the static turning into song",
                                "Hold on to the color of the evening", "We were never meant to stay this long",
                                "Paper moons above the empty street", "Every signal finds a way back home"]

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 26) {
                line(step, current: true)
                line(step + 1, current: false)
            }
            .id(step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 24)),
                                    removal: .opacity.combined(with: .offset(y: -24))))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
        .frame(height: 220, alignment: .top)
        .accessibilityHidden(true)
        .task(id: active) {
            guard active else { return }
            while !Task.isCancelled {
                let count = Self.lines[mod(step)].split(separator: " ").count
                for w in 1...count {
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 60 : 290))
                    if Task.isCancelled { return }
                    withAnimation(.easeOut(duration: 0.25)) { lit = w }
                }
                try? await Task.sleep(for: .milliseconds(1000))
                if Task.isCancelled { return }
                withAnimation(.smooth(duration: 0.55)) { step += 1; lit = 0 }
            }
        }
    }

    private func mod(_ k: Int) -> Int { ((k % Self.lines.count) + Self.lines.count) % Self.lines.count }

    private func line(_ k: Int, current: Bool) -> some View {
        let words = Self.lines[mod(k)].split(separator: " ")
        var text = AttributedString()
        for (i, word) in words.enumerated() {
            var a = AttributedString(String(word) + (i < words.count - 1 ? " " : ""))
            a.foregroundColor = current && i < lit ? Theme.accent : Color.primary.opacity(0.18)
            text += a
        }
        return Text(text)
            .font(.system(size: 30, weight: .bold))
            .tracking(-0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 3 · Search

/// A query types itself into the search pill and comes back as one or two strips of embossed tape.
private struct SearchPill: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typed = ""
    @State private var tapes: [Tape] = []

    private struct Tape: Identifiable {
        let id = UUID()
        let text: String
        let red: Bool
    }

    private static let queries: [(String, [(String, Bool)])] = [
        ("never played", [("0 plays", true)]),
        ("favorites under 3 min", [("★ Favorites", true), ("Under 3:00", false)]),
        ("nie gespielt", [("0 plays", true), ("Deutsch? Klar.", false)]),
        ("something calm for reading", [("Calm", true), ("Slow", false)])
    ]

    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(typed)
                    .font(.system(size: 18, weight: .medium))
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    Capsule().fill(Theme.accent)
                        .frame(width: 2, height: 22)
                        .opacity(active && Int(ctx.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2) ? 1 : 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(Site.card, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.1), radius: 18, y: 12)
            .padding(.horizontal, 30)

            HStack(spacing: 10) {
                ForEach(Array(tapes.enumerated()), id: \.element.id) { k, tape in
                    DymoTape(text: tape.text, color: tape.red ? Theme.accent : Color(white: 0.07))
                        .rotationEffect(.degrees(k.isMultiple(of: 2) ? -2.5 : 2))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(height: 40)
        }
        .accessibilityHidden(true)
        .task(id: active) {
            guard active else { return }
            var q = 0
            while !Task.isCancelled {
                let (query, parts) = Self.queries[q % Self.queries.count]
                for k in 1...query.count {
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 55))
                    if Task.isCancelled { return }
                    typed = String(query.prefix(k))
                }
                try? await Task.sleep(for: .milliseconds(450))
                for part in parts {
                    try? await Task.sleep(for: .milliseconds(170))
                    if Task.isCancelled { return }
                    withAnimation(.spring(duration: 0.6, bounce: 0.4)) { tapes.append(Tape(text: part.0, red: part.1)) }
                }
                try? await Task.sleep(for: .milliseconds(2400))
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.3)) { tapes = [] }
                for k in stride(from: query.count, through: 0, by: -1) {
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 22))
                    if Task.isCancelled { return }
                    typed = String(query.prefix(k))
                }
                try? await Task.sleep(for: .milliseconds(300))
                q += 1
            }
        }
    }
}

/// Embossed label tape like the website's: uppercase, wide-spaced, raised letters on glossy plastic.
private struct DymoTape: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 14, weight: .heavy))
            .tracking(14 * 0.14)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.7), radius: 0, x: 0, y: -1)
            .shadow(color: .white.opacity(0.28), radius: 0, x: 0, y: 1)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.14)).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.4)).frame(height: 2) }
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .shadow(color: .black.opacity(0.35), radius: 7, y: 5)
    }
}

// MARK: - 4 · Mix

/// Two songs as waveforms, one fading out as the other comes in. The fader moves on its own until you grab it.
private struct MixFader: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var value = 0.0
    @State private var touched = false

    var body: some View {
        VStack(spacing: 34) {
            ZStack {
                Waveform(seed: 3) { i, r in 18 + 78 * abs(sin(Double(i) * 0.45)) * (0.5 + r * 0.5) }
                    .foregroundStyle(Theme.accent)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.3), .init(color: .clear, location: 0.85)],
                                         startPoint: .leading, endPoint: .trailing))
                    .opacity(1 - 0.85 * value)
                Waveform(seed: 9) { i, r in 16 + 80 * abs(sin(Double(i) * 0.31 + 1)) * (0.45 + r * 0.55) }
                    .foregroundStyle(.primary)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0.15), .init(color: .black, location: 0.7)],
                                         startPoint: .leading, endPoint: .trailing))
                    .opacity(0.15 + 0.85 * value)
            }
            .frame(height: 110)
            .padding(.horizontal, 30)

            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                        .overlay { Capsule().fill(Theme.accent).frame(width: 2).padding(.vertical, 7) }
                        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.black.opacity(0.15), lineWidth: 0.5) }
                        .frame(width: 52, height: 32)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
                        .offset(x: w * value - 26)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    touched = true
                    value = min(1, max(0, v.location.x / w))
                })
            }
            .frame(height: 44)
            .padding(.horizontal, 56)
        }
        .sensoryFeedback(.selection, trigger: value > 0.5)
        .task(id: active) {
            guard active, !reduceMotion else { return }
            while !Task.isCancelled && !touched {
                withAnimation(.easeInOut(duration: 3)) { value = value < 0.5 ? 1 : 0 }
                try? await Task.sleep(for: .milliseconds(3600))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Crossfader")
        .accessibilityValue(value < 0.5 ? "Song A" : "Song B")
    }
}

/// 48 bars with a fixed pseudo-random spread, so the same song always draws the same wave.
private struct Waveform: View {
    let seed: UInt64
    let height: (Int, Double) -> Double

    var body: some View {
        var state = seed &* 2_654_435_761 &+ 1
        let bars: [Double] = (0..<48).map { i in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return height(i, Double(state >> 33) / Double(UInt64(1) << 31))
        }
        return HStack(spacing: 3) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule().frame(height: 110 * bars[i] / 100)
            }
        }
    }
}

// MARK: - 5 · Things we left out

/// The website's red section: the lines light up one after another.
private struct LeftOutPage: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = 0

    private static let lines = ["No ads.", "No subscription.", "No account.", "Just your music."]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("Things we left out")
                .font(.system(size: 17, weight: .semibold))
                .opacity(0.85)
                .padding(.bottom, 24)
            ForEach(Self.lines.indices, id: \.self) { i in
                Text(Self.lines[i])
                    .font(.system(size: 42, weight: .heavy))
                    .tracking(-1.9)
                    .opacity(i < lit ? 1 : 0.28)
                    .padding(.top, i == Self.lines.count - 1 ? 22 : 0)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .task(id: active) {
            guard active else { lit = 0; return }
            for i in 1...Self.lines.count {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : (i == 1 ? 350 : 420)))
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.35)) { lit = i }
            }
        }
    }
}
