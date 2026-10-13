import SwiftUI

/// 艺人页：热门歌曲 + 专辑
struct ArtistDetailView: View {
    let artist: Artist

    @Environment(Player.self) private var player

    var body: some View {
        AsyncContent(id: artist.id) {
            try await Catalog.artistPage(artist)
        } content: { page in
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    header(page)

                    if !page.songs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("热门歌曲").font(.title2.bold())
                            TrackList(songs: Array(page.songs.prefix(10)), showsArtwork: true)
                        }
                        .padding(.horizontal, Metrics.margin)
                    }

                    if !page.albums.isEmpty {
                        Shelf(title: "专辑", items: page.albums) { CollectionCard(collection: $0) }
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(artist.name)
    }

    private func header(_ page: Catalog.ArtistPage) -> some View {
        HStack(alignment: .bottom, spacing: 28) {
            ArtworkView(seed: artist.artworkSeed, url: page.artist.artworkURL)
                .clipShape(.circle)
                .frame(width: 200, height: 200)
                .shadow(color: .black.opacity(0.2), radius: 14, y: 6)

            VStack(alignment: .leading, spacing: 14) {
                Text(artist.name).font(.system(size: 34, weight: .bold))
                Button { player.play(page.songs) } label: {
                    Label("播放热门歌曲", systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(page.songs.isEmpty)
            }
        }
        .padding(.horizontal, Metrics.margin)
    }
}
