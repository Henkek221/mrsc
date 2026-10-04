import SwiftUI

/// Settings › About MRSC: the stamped logo, the version, and where MRSC lives online.
/// Donations stay one step away on the website, so the app itself never asks for money.
struct AboutView: View {
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BrandStyle.key) private var styleRaw = BrandStyle.red.rawValue
    @State private var stamped = [Bool](repeating: false, count: 4)
    @State private var shake = CGSize.zero
    @State private var playing: Task<Void, Never>?

    private var style: BrandStyle { BrandStyle(rawValue: styleRaw) ?? .red }

    var body: some View {
        List {
            Section {
                VStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 120 * 0.225, style: .continuous).fill(style.color)
                        StampLogo(stamped: stamped).padding(14).offset(shake)
                    }
                    .frame(width: 120, height: 120)
                    .shadow(color: style.color.opacity(0.35), radius: 18, y: 10)
                    .contentShape(Rectangle())
                    .onTapGesture { play() }
                    .accessibilityLabel("MRSC")
                    .accessibilityAddTraits(.isImage)

                    Text("MRSC")
                        .siteHeadline(34)
                        .padding(.top, 22)
                    Text("Version \(AppVersion.marketing) (\(AppVersion.build))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    Text("The music player with way too many settings.")
                        .siteLede(17)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                linkRow("Website", symbol: "globe", colors: [.pink, .red], url: Links.website)
                linkRow("Source Code on GitHub", symbol: "chevron.left.forwardslash.chevron.right", colors: [Color(white: 0.32), Color(white: 0.08)], url: Links.github)
                linkRow("Discord", symbol: "bubble.left.and.bubble.right.fill", colors: [Color(red: 0.45, green: 0.5, blue: 1), Color(red: 0.34, green: 0.38, blue: 0.95)], url: Links.discord)
            } footer: {
                Text("MRSC is open source under the GPL-3.0. Bug reports, ideas and pull requests are welcome on GitHub, themes and questions on Discord.")
            }

            Section {
                Button("Show Welcome Again") { router.replayOnboarding() }
            } footer: {
                Text("Free. No ads, no subscription, no account.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if reduceMotion { stamped = stamped.map { _ in true } } else { play() }
        }
        .onDisappear { playing?.cancel() }
    }

    private func linkRow(_ title: String, symbol: String, colors: [Color], url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                GradientIcon(symbol: symbol, colors: colors, size: 30)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func play() {
        playing?.cancel()
        stamped = stamped.map { _ in false }
        playing = Task {
            try? await Task.sleep(for: .milliseconds(200))
            await playStamps($stamped, shake: $shake, gap: 260)
        }
    }
}

enum AppVersion {
    static var marketing: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}
