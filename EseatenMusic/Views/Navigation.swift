import SwiftUI

/// 所有可以推入 NavigationStack 的页面
enum Destination: Hashable {
    case album(Album)
    case playlist(Playlist)
    case artist(Artist)
}

extension View {
    /// 统一注册目标页面，并给每个页面留出播放条的空间
    func appDestinations() -> some View {
        navigationDestination(for: Destination.self) { destination in
            Group {
                switch destination {
                case .album(let album):
                    CollectionDetailView(collection: album)
                case .playlist(let playlist):
                    CollectionDetailView(collection: playlist)
                case .artist(let artist):
                    ArtistDetailView(artist: artist)
                }
            }
            .reservingPlayerBarSpace()
        }
    }

    /// 在页面底部让出全局播放条的高度，内容仍可从播放条下面滚过。
    /// macOS 会接管 detail 列里的 NavigationStack，外层的 inset 传不进推入的页面，
    /// 所以根页面和每个目标页面各加一次（目标页面已由 `appDestinations()` 统一处理）。
    func reservingPlayerBarSpace() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: Metrics.playerBarClearance)
        }
    }
}
