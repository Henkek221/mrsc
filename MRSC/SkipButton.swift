import SwiftUI

/// Next / Previous button whose triangles flow through the icon on every tap, the way Apple Music's do:
/// the leading triangle shrinks out, the trailing one slides into its place and a new one grows in behind.
struct SkipButton: View {
    enum Direction { case forward, backward }

    let direction: Direction
    /// Matches the point size the `forward.fill` / `backward.fill` symbol would have had.
    let size: CGFloat
    /// The tappable area around the glyph; it never changes while the triangles move.
    var box: CGSize
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts taps. Each whole step is one full pass of the triangles; the glyph only looks at the fraction,
    /// so taps landing mid-flight just retarget the spring and the icon always settles back to rest.
    @State private var steps: Double = 0

    var body: some View {
        Button {
            if reduceMotion {
                steps += 1
            } else {
                withAnimation(.spring(duration: 0.42, bounce: 0)) { steps += 1 }
            }
            action()
        } label: {
            SkipGlyph(progress: steps, size: size)
                .scaleEffect(x: direction == .forward ? 1 : -1)
                .frame(width: box.width, height: box.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(SkipPressStyle(diameter: max(box.width, box.height)))
        .accessibilityLabel(direction == .forward ? "Next" : "Previous")
    }
}

/// Apple Music's press feel: a soft circle blooms behind the icon and the whole thing dips in a little,
/// then springs back on release.
private struct SkipPressStyle: ButtonStyle {
    let diameter: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.quaternary)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(configuration.isPressed ? 1 : 0.6)
                    .opacity(configuration.isPressed ? 1 : 0)
            }
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(configuration.isPressed ? .spring(duration: 0.2, bounce: 0) : .spring(duration: 0.4, bounce: 0.3),
                       value: configuration.isPressed)
    }
}

/// The two triangles of `forward.fill`, drawn as three independently placed triangles so they can move.
/// Slot positions run along the icon: −1 is the empty point at the trailing edge, 0 and 1 are the two
/// resting triangles, 2 is the empty point at the leading edge. Advancing `progress` by 1 shifts every
/// triangle one slot forward, which leaves the icon exactly as it started.
private struct SkipGlyph: View, Animatable {
    var progress: Double
    let size: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    // Proportions measured from the regular-weight SF Symbol.
    private var triangleWidth: CGFloat { size * 0.661 }
    private var triangleHeight: CGFloat { size * 0.7425 }

    var body: some View {
        let phase = progress - progress.rounded(.down)
        ZStack {
            ForEach(-1..<2) { slot in
                triangle(at: Double(slot) + phase)
            }
        }
        .frame(width: triangleWidth * 2, height: triangleHeight)
    }

    /// A triangle at a fractional slot. Between 0 and 1 it only slides; past either end it also shrinks
    /// and fades toward the icon's edge, staying flush against its neighbour the whole way.
    private func triangle(at slot: Double) -> some View {
        let w = triangleWidth
        let scale: CGFloat
        let x: CGFloat
        if slot < 0 {
            scale = max(0, 1 + slot)
            x = -w / 2 + slot * w / 2
        } else if slot > 1 {
            scale = max(0, 2 - slot)
            x = w / 2 + (slot - 1) * w / 2
        } else {
            scale = 1
            x = (slot - 0.5) * w
        }
        return RoundedTriangle()
            .frame(width: w, height: triangleHeight)
            .scaleEffect(scale)
            .opacity(Double(scale))
            .offset(x: x)
    }
}

/// A right-pointing triangle with softened corners, like the ones in the `forward.fill` symbol.
private struct RoundedTriangle: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let r = rect.height * 0.065
        let top = CGPoint(x: rect.minX, y: rect.minY)
        let tip = CGPoint(x: rect.maxX, y: rect.midY)
        let bottom = CGPoint(x: rect.minX, y: rect.maxY)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addArc(tangent1End: top, tangent2End: tip, radius: r)
        p.addArc(tangent1End: tip, tangent2End: bottom, radius: r)
        p.addArc(tangent1End: bottom, tangent2End: top, radius: r)
        p.closeSubpath()
        return p
    }
}
