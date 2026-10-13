import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarItem? = .home
    /// 搜索状态放在这里，切到别的页面再回来时还在
    @State private var search = SearchModel()
    @State private var path: [Destination] = []
    /// detail 列的宽度。它总贴着窗口右边，所以播放条靠右下对齐、只需要宽度
    @State private var detailWidth: CGFloat = 0
    @State private var showsLogin = false
    @State private var panel: SidePanel?
    /// 全屏的“正在播放”
    @State private var showsNowPlaying = false
    @State private var toast: Toast?

    @Environment(Account.self) private var account
    @Environment(Player.self) private var player

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            // macOS 会接管 detail 列里的 NavigationStack，推入的页面会盖住同一列里的
            // overlay / ZStack 兄弟视图，外层的 safeAreaInset 也传不进去。
            // 所以播放条挂在 NavigationSplitView 外层，每个页面只加无状态的底部留白。
            NavigationStack(path: $path) {
                detail
                    .reservingPlayerBarSpace()
                    .appDestinations()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
        }
        // 全局唯一的播放条和右侧面板，叠在整个分栏视图之上，宽度对齐 detail 列。
        // 面板浮在页面上、停在播放条上方，打开关闭时播放条和页面的宽度都不变。
        .overlay(alignment: .bottomTrailing) {
            if detailWidth > 0 && !showsNowPlaying {
                ZStack(alignment: .bottomTrailing) {
                    PlayerBar(panel: $panel) { setNowPlaying(true) }
                        .frame(maxWidth: .infinity)
                    if let panel {
                        SidePanelView(kind: panel) {
                            withAnimation(.spring(duration: 0.4, bounce: 0.1)) { self.panel = nil }
                        }
                        .frame(width: Metrics.sidePanelWidth)
                        .frame(maxHeight: .infinity)
                        .padding([.top, .trailing], Metrics.playerBarBottomMargin)
                        .padding(.bottom, Metrics.playerBarClearance)
                        // padding 要在 transition 之前，滑出时才能整个移出窗口
                        .transition(.move(edge: .trailing))
                    }
                }
                .frame(width: detailWidth)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        // 全屏“正在播放”盖住整个窗口（包括侧边栏），工具栏由它自己收起，只留红绿灯
        .overlay {
            if showsNowPlaying, let song = player.current {
                NowPlayingView(song: song) { setNowPlaying(false) }
                    .transition(.move(edge: .bottom))
            }
        }
        // 轻提示放在最上层，全屏“正在播放”里也看得到
        .overlay(alignment: .bottom) {
            if let toast {
                ToastView(toast: toast)
                    .padding(.bottom, Metrics.playerBarClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .task(id: toast?.id) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { toast = nil }
        }
        .sheet(isPresented: $showsLogin) { LoginSheet() }
        .environment(\.openLogin) { showsLogin = true }
        .environment(\.showToast) { newToast in
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { toast = newToast }
        }
        .environment(\.navigate) { destination in
            setNowPlaying(false)
            path.append(destination)
        }
        .onChange(of: selection) { path = [] }
    }

    private func setNowPlaying(_ isShown: Bool) {
        withAnimation(.spring(duration: 0.5, bounce: 0.08)) { showsNowPlaying = isShown }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .home {
        case .search: SearchView(model: search)
        case .home: HomeView()
        case .explore: NewView()
        case .radio: RadioView()
        case .likedSongs:
            library("我喜欢的音乐") {
                if let liked = account.likedPlaylist {
                    CollectionDetailView(collection: liked).id(liked.id)
                }
            }
        case .daily:
            library("每日推荐") {
                AsyncContent { try await Catalog.dailyPlaylist() } content: {
                    CollectionDetailView(collection: $0)
                }
            }
        case .recents:
            library("最近播放") {
                AsyncContent { try await Catalog.recentSongs() } content: {
                    SongsView(title: "最近播放", songs: $0)
                }
            }
        case .collections:
            library("我的收藏") { CollectionsView() }
        case .cloud:
            library("音乐云盘") {
                AsyncContent { try await Catalog.cloudSongs() } content: {
                    SongsView(title: "音乐云盘", songs: $0)
                }
            }
        case .playlist(let id):
            if let playlist = account.playlist(id) {
                // 换歌单时重建页面，不沿用上一个歌单已加载的歌曲
                CollectionDetailView(collection: playlist).id(id)
            }
        }
    }

    /// “我的”里的页面需要登录，未登录时显示登录提示
    @ViewBuilder
    private func library<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        if account.isLoggedIn {
            content()
        } else if account.isRestoring {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LoginPrompt(title: title)
        }
    }
}

#Preview {
    ContentView()
        .environment(Player())
        .environment(Account())
        .frame(width: 1200, height: 780)
}
