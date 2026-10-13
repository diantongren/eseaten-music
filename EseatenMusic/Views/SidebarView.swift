import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    @Environment(Account.self) private var account
    @Environment(Player.self) private var player
    @State private var showsNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var pendingRemoval: Playlist?
    @State private var failure: String?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("搜索", systemImage: "magnifyingglass").tag(SidebarItem.search)
                Label("推荐", systemImage: "house.fill").tag(SidebarItem.home)
                Label("精选", systemImage: "square.grid.2x2.fill").tag(SidebarItem.explore)
                Label("漫游", systemImage: "wave.3.right.circle.fill").tag(SidebarItem.radio)
            }

            if account.isLoggedIn {
                Section("我的") {
                    Label("我喜欢的音乐", systemImage: "heart.fill").tag(SidebarItem.likedSongs)
                    Label("每日推荐", systemImage: "calendar").tag(SidebarItem.daily)
                    Label("最近播放", systemImage: "clock.fill").tag(SidebarItem.recents)
                    Label("我的收藏", systemImage: "star.fill").tag(SidebarItem.collections)
                    Label("音乐云盘", systemImage: "icloud.fill").tag(SidebarItem.cloud)
                }

                Section {
                    ForEach(account.createdPlaylists) { playlistRow($0) }
                } header: {
                    HStack {
                        Text("创建的歌单")
                        Spacer()
                        Button { showsNewPlaylist = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 20, height: 20)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help("新建歌单")
                        // 分区标题会延伸到侧边栏边缘，往里收一点，和下面歌单行的右边对齐
                        .padding(.trailing, 8)
                    }
                }

                if !account.collectedPlaylists.isEmpty {
                    Section("收藏的歌单") {
                        ForEach(account.collectedPlaylists) { playlistRow($0) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // 和网易云 / Apple Music 一样，侧边栏图标用强调色
        .listItemTint(.accentColor)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AccountBadge().padding(10)
        }
        .alert("新建歌单", isPresented: $showsNewPlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("创建") { createPlaylist() }
            Button("取消", role: .cancel) { newPlaylistName = "" }
        }
        .confirmationDialog(
            removalTitle, isPresented: Binding { pendingRemoval != nil } set: { if !$0 { pendingRemoval = nil } }
        ) {
            Button(removalAction, role: .destructive) { removePendingPlaylist() }
        }
        .alert("操作失败", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
        } message: {
            Text(failure ?? "")
        }
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        Label {
            Text(playlist.title).lineLimit(1)
        } icon: {
            ArtworkView(seed: playlist.artworkSeed, url: playlist.artworkURL, cornerRadius: 4)
                .frame(width: 20, height: 20)
        }
        .tag(SidebarItem.playlist(playlist.id))
        .contextMenu {
            Button("播放") { player.play(playlist.destination) }
            Divider()
            Button(account.createdPlaylists.contains(playlist) ? "删除歌单…" : "取消收藏…", role: .destructive) {
                pendingRemoval = playlist
            }
        }
    }

    // MARK: - 歌单管理

    private var removalTitle: String {
        guard let pendingRemoval else { return "" }
        return account.createdPlaylists.contains(pendingRemoval)
            ? "删除歌单“\(pendingRemoval.title)”？删除后无法恢复。"
            : "取消收藏“\(pendingRemoval.title)”？"
    }

    private var removalAction: String {
        pendingRemoval.map { account.createdPlaylists.contains($0) } == true ? "删除" : "取消收藏"
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        newPlaylistName = ""
        guard !name.isEmpty else { return }
        Task {
            do { try await account.createPlaylist(named: name) } catch { failure = error.localizedDescription }
        }
    }

    private func removePendingPlaylist() {
        guard let playlist = pendingRemoval else { return }
        pendingRemoval = nil
        if selection == .playlist(playlist.id) { selection = .home }
        Task {
            do { try await account.remove(playlist) } catch { failure = error.localizedDescription }
        }
    }
}

/// 侧边栏底部：已登录显示头像和昵称，未登录显示登录按钮
private struct AccountBadge: View {
    @Environment(Account.self) private var account
    @Environment(\.openLogin) private var openLogin

    var body: some View {
        if let profile = account.profile {
            Menu {
                Button("刷新歌单") { Task { await account.reload() } }
                Button("退出登录", role: .destructive) { Task { await account.logout() } }
            } label: {
                HStack(spacing: 8) {
                    AsyncImage(url: .netease(profile.avatarUrl)?.neteaseThumbnail(points: 26)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                    }
                    .frame(width: 26, height: 26)
                    .clipShape(.circle)
                    Text(profile.nickname).lineLimit(1)
                    if profile.vipType > 0 {
                        Text("VIP").font(.caption2.bold()).foregroundStyle(.tint)
                    }
                    Spacer(minLength: 0)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        } else if !account.isRestoring {
            Button(action: openLogin) {
                Label("登录网易云音乐", systemImage: "person.crop.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }
}
