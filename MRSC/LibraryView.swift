import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @Environment(SourceManager.self) private var sources
    @Environment(LayoutStore.self) private var layout
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Three across on iPhone; the six pinned items fit one row on iPad.
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 14), count: sizeClass == .regular ? 6 : 3) }

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
                        .font(.app(size: 13))
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

    private struct Category: Identifiable {
        let title: String, symbol: String, route: Route, count: Int?
        var id: String { title }
    }

    /// Only music lives here; tools (Sound, Files, Sources) are in Settings.
    private var categoryItems: [Category] {
        var items: [Category] = [
            .init(title: "Songs", symbol: "music.note", route: .songs, count: library.tracks.count),
            .init(title: "Playlists", symbol: "music.note.list", route: .playlists, count: library.playlists.count),
            .init(title: "Artists", symbol: "music.microphone", route: .artists, count: library.artistEntries.count),
            .init(title: "Albums", symbol: "square.stack", route: .albums, count: library.albumEntries.count),
            .init(title: "Favorites", symbol: "star", route: .favorites, count: library.tracks.filter(\.isFavorite).count),
            .init(title: "Recently Played", symbol: "clock", route: .recentlyPlayed, count: nil),
            .init(title: "Radio", symbol: "dot.radiowaves.left.and.right", route: .radio, count: nil),
        ]
        if sources.hasSources || library.tracks.contains(where: \.isRemote) {
            items.append(.init(title: "Downloads", symbol: "arrow.down.circle", route: .downloads, count: library.tracks.filter(\.isDownloaded).count))
        }
        return items
    }

    /// Apple Music-style list: accent symbol, title, count and chevron, separators start at the title.
    private var categories: some View {
        let items = categoryItems
        return VStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
                if item.id != items.last?.id {
                    Divider().padding(.leading, Self.iconWidth + Self.iconSpacing)
                }
            }
        }
    }

    private static let iconWidth: CGFloat = 30
    private static let iconSpacing: CGFloat = 14

    private func row(_ item: Category) -> some View {
        NavigationLink(value: item.route) {
            HStack(spacing: Self.iconSpacing) {
                Image(systemName: item.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                    .frame(width: Self.iconWidth)
                    .accessibilityHidden(true)
                Text(item.title).font(.app(size: 21))
                Spacer()
                if let count = item.count { Text("\(count)").font(.app(size: 15)).foregroundStyle(.tertiary) }
                Image(systemName: "chevron.right").font(.app(size: 14, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .frame(minHeight: 52)
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
                .font(.app(size: 13, weight: .medium))
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
            Text(entry.title).font(.app(size: 16, weight: .semibold))
        }
        .padding(14)
    }
}
