import SwiftUI

/// 专辑 / 歌单网格
struct CollectionGridView<C: TrackCollection>: View {
    let title: String
    let items: [C]
    var emptyText = "还没有专辑"
    /// 右键菜单里的“取消收藏”，为 nil 时没有右键菜单
    var onRemove: ((C) -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(title)
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(items) { item in
                        CollectionCard(collection: item, width: nil)
                            .contextMenu {
                                if let onRemove {
                                    Button("取消收藏", role: .destructive) { onRemove(item) }
                                }
                            }
                    }
                }
                .padding(.horizontal, Metrics.margin)
            }
            .padding(.vertical, 20)
        }
        .overlay {
            if items.isEmpty { ContentUnavailableView(emptyText, systemImage: "square.stack") }
        }
        .navigationTitle(title)
    }
}

struct ArtistsView: View {
    var title = "艺人"
    let artists: [Artist]
    var emptyText = "还没有歌手"

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 24, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(title)
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(artists) { artist in
                        NavigationLink(value: Destination.artist(artist)) {
                            VStack(spacing: 10) {
                                ArtworkView(seed: artist.artworkSeed, url: artist.artworkURL)
                                    .clipShape(.circle)
                                    .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                                Text(artist.name).font(.callout.weight(.medium)).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Metrics.margin)
            }
            .padding(.vertical, 20)
        }
        .overlay {
            if artists.isEmpty { ContentUnavailableView(emptyText, systemImage: "music.microphone") }
        }
        .navigationTitle(title)
    }
}

struct SongsView: View {
    let title: String
    let songs: [Song]

    @Environment(Player.self) private var player
    @State private var selection = Set<Song.ID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageTitle(title)
                .padding(.top, 20)

            Table(songs, selection: $selection) {
                TableColumn("标题") { song in
                    HStack(spacing: 10) {
                        ArtworkView(seed: song.artworkSeed, url: song.artworkURL, cornerRadius: 3)
                            .frame(width: 26, height: 26)
                        Text(song.title)
                        if player.current?.id == song.id {
                            NowPlayingIndicator(isPlaying: player.isPlaying)
                        }
                    }
                }
                TableColumn("艺人", value: \.artist)
                TableColumn("专辑", value: \.album)
                TableColumn("时长") { song in
                    Text(song.duration.mmss).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(56)
                TableColumn("") { song in
                    SongMenuButton(song: song).foregroundStyle(.secondary)
                }
                .width(28)
            }
            .overlay {
                if songs.isEmpty { ContentUnavailableView("没有歌曲", systemImage: "music.note") }
            }
            .contextMenu(forSelectionType: Song.ID.self) { ids in
                Button("播放") { play(ids) }
                if ids.count == 1, let song = songs.first(where: { ids.contains($0.id) }) {
                    Divider()
                    SongMenuItems(song: song)
                }
            } primaryAction: { ids in
                play(ids)
            }
        }
        .navigationTitle(title)
    }

    private func play(_ ids: Set<Song.ID>) {
        guard let song = songs.first(where: { ids.contains($0.id) }) else { return }
        player.play(song, in: songs)
    }
}
