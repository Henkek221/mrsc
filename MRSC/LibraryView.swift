import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @Environment(SourceManager.self) private var sources
    @Environment(LayoutStore.self) private var layout

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if library.tracks.isEmpty {
                    EmptyLibraryCard().padding(.bottom, 18)
                }

                if !library.pinnedEntries.isEmpty {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(library.pinnedEntries) { entry in
                            NavigationLink(value: entry.route) { PinnedCell(entry: entry) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    EntryMenuItems(entry: entry)
                                } preview: {
                                    PinnedPreview(entry: entry)
                                }
                        }
                    }
                    .padding(.bottom, 8)
                    .transition(.opacity)
                } else if !library.tracks.isEmpty {
                    Text("Touch and hold a playlist, artist or album and choose Pin to show it here.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                }

                if !library.tracks.isEmpty { categories }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .animation(.smooth, value: library.pinned)
        .animation(.smooth, value: library.tracks.isEmpty)
        .trackScroll()
        .navigationTitle("Library")
        .toolbar {
            if !layout.usesClassicBar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.openAddMusic() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Music")
                }
            }
            if !library.tracks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.organize) { Image(systemName: "wand.and.stars") }
                        .accessibilityLabel("Organize")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.showSettings = true } label: { Image(systemName: "gearshape.fill") }
                    .accessibilityLabel("Settings")
            }
        }
    }

    /// Only music lives here; tools (Sound, Files, Sources) are in Settings.
    private var categories: some View {
        VStack(spacing: 0) {
            row("Songs", "music.note", [.orange, Color(red: 1, green: 0.6, blue: 0.1)], .songs, library.tracks.count)
            row("Playlists", "music.note.list", [Color(red: 0.55, green: 0.47, blue: 1), Color(red: 0.3, green: 0.25, blue: 0.9)], .playlists, library.playlists.count)
            row("Artists", "music.mic", [Color(red: 0.95, green: 0.4, blue: 0.97), Color(red: 0.7, green: 0.15, blue: 0.88)], .artists, library.artistEntries.count)
            row("Albums", "square.stack.fill", [Color(red: 1, green: 0.4, blue: 0.5), Color(red: 0.96, green: 0.15, blue: 0.35)], .albums, library.albumEntries.count)
            row("Favorites", "star.fill", [Color(red: 1, green: 0.8, blue: 0.2), Color(red: 0.95, green: 0.55, blue: 0.1)], .favorites, library.tracks.filter(\.isFavorite).count)
            row("Recently Played", "clock.fill", [Color(red: 0.45, green: 0.75, blue: 1), Color(red: 0.2, green: 0.45, blue: 0.95)], .recentlyPlayed, nil)
            row("Radio", "dot.radiowaves.left.and.right", [Color(red: 1, green: 0.35, blue: 0.55), Color(red: 0.75, green: 0.1, blue: 0.5)], .radio, nil)
            if sources.hasSources || library.tracks.contains(where: \.isRemote) {
                row("Downloads", "arrow.down.circle.fill", [Color(red: 0.3, green: 0.85, blue: 0.5), Color(red: 0.1, green: 0.6, blue: 0.35)], .downloads, library.tracks.filter(\.isDownloaded).count)
            }
        }
    }

    private func row(_ title: String, _ symbol: String, _ colors: [Color], _ route: Route, _ count: Int?) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 16) {
                GradientIcon(symbol: symbol, colors: colors)
                Text(title).font(.system(size: 21))
                Spacer()
                if let count { Text("\(count)").font(.system(size: 15)).foregroundStyle(.tertiary) }
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PinnedCell: View {
    let entry: LibraryEntry
    var body: some View {
        VStack(spacing: 8) {
            ArtworkView(entry: entry, radius: 12)
            Text(entry.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }
}

struct PinnedPreview: View {
    let entry: LibraryEntry
    var body: some View {
        VStack(spacing: 10) {
            ArtworkView(entry: entry, radius: 16).frame(width: 190, height: 190)
            Text(entry.title).font(.system(size: 16, weight: .semibold))
        }
        .padding(14)
    }
}
