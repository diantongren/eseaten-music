import SwiftUI

struct NewView: View {
    var body: some View {
        AsyncContent {
            try await Catalog.discover()
        } content: { discover in
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    PageTitle("精选")
                    Shelf(title: "新碟上架", items: discover.newAlbums) { CollectionCard(collection: $0, width: 200) }
                    Shelf(title: "热门歌单", items: discover.hotPlaylists) { CollectionCard(collection: $0) }
                    Shelf(title: "精品歌单", items: discover.highQualityPlaylists) { CollectionCard(collection: $0) }
                }
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("精选")
    }
}

struct RadioView: View {
    @Environment(Player.self) private var player
    @Environment(Account.self) private var account
    @Environment(\.openLogin) private var openLogin

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                PageTitle("漫游")
                banner

                VStack(alignment: .leading, spacing: 12) {
                    Text("排行榜").font(.title2.bold()).padding(.horizontal, Metrics.margin)
                    AsyncContent {
                        try await Catalog.toplists()
                    } content: { toplists in
                        LazyVGrid(columns: columns, spacing: 26) {
                            ForEach(toplists) { CollectionCard(collection: $0, width: nil) }
                        }
                        .padding(.horizontal, Metrics.margin)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .navigationTitle("漫游")
    }

    /// 私人漫游横幅
    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.14, blue: 0.26), Color(red: 0.45, green: 0.05, blue: 0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("私人").font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.25), in: .capsule)
                Text("私人漫游").font(.system(size: 34, weight: .heavy))
                Text(account.isLoggedIn ? "根据你的口味不间断播放" : "登录网易云音乐后收听").font(.callout).opacity(0.85)
                Button {
                    if account.isLoggedIn { player.playRadio(Catalog.personalFM) } else { openLogin() }
                } label: {
                    Label(account.isLoggedIn ? "收听" : "登录", systemImage: account.isLoggedIn ? "play.fill" : "person.fill")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(28)
        }
        .frame(height: 260)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, Metrics.margin)
    }
}
