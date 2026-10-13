import SwiftUI

/// 我的收藏：收藏的专辑和关注的歌手
struct CollectionsView: View {
    enum Tab: String, CaseIterable {
        case albums = "专辑"
        case artists = "歌手"
    }

    @Environment(Account.self) private var account
    @State private var tab = Tab.albums
    /// 刚取消收藏的专辑，先从网格里拿掉，不必重新加载
    @State private var removedAlbums: Set<Album.ID> = []
    @State private var failure: String?

    var body: some View {
        Group {
            switch tab {
            case .albums:
                AsyncContent { try await Catalog.likedAlbums() } content: { albums in
                    CollectionGridView(title: "我的收藏", items: albums.filter { !removedAlbums.contains($0.id) },
                                       onRemove: uncollect)
                }
            case .artists:
                AsyncContent { try await Catalog.likedArtists() } content: {
                    ArtistsView(title: "我的收藏", artists: $0)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("类型", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .alert("操作失败", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
        } message: {
            Text(failure ?? "")
        }
    }

    private func uncollect(_ album: Album) {
        withAnimation { _ = removedAlbums.insert(album.id) }
        Task {
            do {
                try await account.setCollected(album, false)
            } catch {
                removedAlbums.remove(album.id)
                failure = "取消收藏“\(album.title)”失败：\(error.localizedDescription)"
            }
        }
    }
}
