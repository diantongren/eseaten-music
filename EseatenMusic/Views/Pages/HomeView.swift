import SwiftUI

struct HomeView: View {
    @Environment(Account.self) private var account

    var body: some View {
        AsyncContent(id: account.isLoggedIn) {
            try await Catalog.home(loggedIn: account.isLoggedIn)
        } content: { home in
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    PageTitle("推荐")

                    Shelf(title: "置顶精选", items: home.topPicks) { TopPickCard(playlist: $0) }

                    Shelf(title: account.isLoggedIn ? "每日推荐歌单" : "为你推荐的播放列表", items: home.playlists) {
                        CollectionCard(collection: $0)
                    }

                    Shelf(title: "新歌速递", items: home.newSongAlbums) { CollectionCard(collection: $0, width: 150) }
                }
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("推荐")
    }
}

/// “置顶精选”的大卡片：上方封面，下方取封面色调的说明块
private struct TopPickCard: View {
    let playlist: Playlist

    /// 去重后的前三位艺人
    private var featuredArtists: String {
        var seen = Set<String>()
        return playlist.songs.map(\.artist).filter { seen.insert($0).inserted }.prefix(3).joined(separator: "、")
    }

    var body: some View {
        NavigationLink(value: playlist.destination) {
            VStack(spacing: 0) {
                ArtworkView(seed: playlist.artworkSeed, url: playlist.artworkURL, cornerRadius: 0, label: playlist.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.blurb ?? featuredArtists)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    Text(playlist.curator)
                        .font(.caption)
                        .opacity(0.8)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .padding(14)
                .background(Color(hue: Double(playlist.artworkSeed % 360) / 360, saturation: 0.7, brightness: 0.35))
            }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .frame(width: 260)
    }
}
