import SwiftUI

/// 专辑 / 播放列表卡片；悬停时浮出玻璃播放按钮
struct CollectionCard<C: TrackCollection>: View {
    let collection: C
    /// nil 时填满父容器宽度（用于网格）
    var width: CGFloat? = 180
    /// 替换第二行的艺人 / 创建者，比如同一艺人的专辑货架改显示年份
    var subtitle: String? = nil

    @Environment(Player.self) private var player
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: collection.destination) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkView(seed: collection.artworkSeed, url: collection.artworkURL, label: collection.artworkLabel)
                    .shadow(color: .black.opacity(isHovering ? 0.22 : 0.12), radius: isHovering ? 10 : 5, y: 3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(collection.title).font(.callout.weight(.medium))
                    Text(subtitle ?? collection.subtitle).font(.callout).foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        // 按钮放在 NavigationLink 外面，避免点播放时触发跳转
        .overlay(alignment: .top) {
            if isHovering {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        Button { player.play(collection.destination) } label: {
                            Image(systemName: "play.fill").font(.title3)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .padding(10)
                    }
                    .transition(.opacity)
            }
        }
        .frame(width: width)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}
