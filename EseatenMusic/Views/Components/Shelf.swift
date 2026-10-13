import SwiftUI

/// 页面顶部的大标题
struct PageTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .bold))
            .padding(.horizontal, Metrics.margin)
    }
}

/// 首页那种带标题的横向货架。
/// 和 Apple Music 一样不显示滚动条（接鼠标时系统会强制显示），
/// 鼠标移上去时两侧出现翻页按钮，一次翻一屏。
struct Shelf<Item: Identifiable, Card: View>: View where Item.ID: Sendable {
    let title: String
    let items: [Item]
    /// 点标题跳转的“更多”页面；有它时标题后面才显示箭头
    var destination: Destination? = nil
    @ViewBuilder var card: (Item) -> Card

    @State private var position = ScrollPosition(idType: Item.ID.self)
    /// 当前完整露出来的卡片
    @State private var visible: Set<Item.ID> = []
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let destination {
                    NavigationLink(value: destination) {
                        HStack(spacing: 4) {
                            heading
                            Image(systemName: "chevron.right")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    heading
                }
            }
            .padding(.horizontal, Metrics.margin)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(items) { card($0) }
                }
                .scrollTargetLayout()
            }
            // .hidden 在接了鼠标时仍会显示滚动条，.never 才能彻底去掉
            .scrollIndicators(.never)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition($position)
            .contentMargins(.horizontal, Metrics.margin, for: .scrollContent)
            .onScrollTargetVisibilityChange(idType: Item.ID.self, threshold: 0.95) { visible = Set($0) }
            .overlay(alignment: .leading) {
                pageButton("chevron.left", isShown: canGoBack) { page(by: -1) }
            }
            .overlay(alignment: .trailing) {
                pageButton("chevron.right", isShown: canGoForward) { page(by: 1) }
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .animation(.easeOut(duration: 0.15), value: visible)
        }
    }

    private var heading: some View {
        Text(title).font(.title2.bold())
    }

    private var visibleIndices: [Int] {
        items.indices.filter { visible.contains(items[$0].id) }
    }

    private var canGoBack: Bool {
        guard let first = items.first else { return false }
        return !visible.isEmpty && !visible.contains(first.id)
    }

    private var canGoForward: Bool {
        guard let last = items.last else { return false }
        return !visible.isEmpty && !visible.contains(last.id)
    }

    /// 往前或往后翻一屏：下一屏的第一张卡片对齐到左边距
    private func page(by direction: Int) {
        let indices = visibleIndices
        guard let first = indices.first, let last = indices.last else { return }
        let target = direction > 0
            ? min(last + 1, items.count - 1)
            : max(first - indices.count, 0)
        withAnimation(.smooth) {
            position.scrollTo(id: items[target].id, anchor: .leading)
        }
    }

    private func pageButton(_ systemImage: String, isShown: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 28, height: 52)
                // Apple Music 用的是磨砂材质：模糊下面的封面、提亮，几乎不透明，不是 Liquid Glass
                .background(.regularMaterial, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // 和 Apple Music 一样骑在卡片边缘上
        .padding(.horizontal, Metrics.margin - 14)
        .opacity(isHovering && isShown ? 1 : 0)
        .allowsHitTesting(isHovering && isShown)
    }
}
