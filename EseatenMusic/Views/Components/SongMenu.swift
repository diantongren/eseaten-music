import SwiftUI

/// 歌曲的“…”菜单和右键菜单共用的选项：喜爱、添加到歌单、从歌单中删除、前往歌手。
/// 结果都用轻提示告诉用户
struct SongMenuItems: View {
    let song: Song
    /// 自己创建的歌单；传入时多一项“从歌单中删除”
    var playlist: Playlist? = nil
    /// 删除成功后让列表把这一行拿掉
    var onRemoved: () -> Void = {}

    @Environment(Account.self) private var account
    @Environment(\.openLogin) private var openLogin
    @Environment(\.navigate) private var navigate
    @Environment(\.showToast) private var showToast

    var body: some View {
        if account.isLoggedIn {
            let isLiked = account.likedSongIDs.contains(song.id)
            Button(isLiked ? "取消喜爱" : "喜爱", systemImage: isLiked ? "heart.slash" : "heart", action: toggleLike)

            Menu {
                AddToPlaylistItems(song: song)
            } label: {
                Label("添加到歌单", systemImage: "text.badge.plus")
            }

            if let playlist {
                Button("从歌单中删除", systemImage: "trash", role: .destructive) { remove(from: playlist) }
            }
        } else {
            Button("登录后喜爱或添加到歌单", systemImage: "person.crop.circle", action: openLogin)
        }

        if !song.artists.isEmpty {
            Divider()
        }
        if let artist = song.artists.first, song.artists.count == 1 {
            Button("前往歌手", systemImage: "music.microphone") { navigate(.artist(artist)) }
        } else if !song.artists.isEmpty {
            Menu {
                ForEach(song.artists) { artist in
                    Button(artist.name) { navigate(.artist(artist)) }
                }
            } label: {
                Label("前往歌手", systemImage: "music.microphone")
            }
        }
    }

    private func toggleLike() {
        let like = !account.likedSongIDs.contains(song.id)
        Task {
            do {
                try await account.toggleLike(song)
                showToast(Toast(message: like ? "已喜爱“\(song.title)”" : "已取消喜爱“\(song.title)”"))
            } catch {
                showToast(Toast(message: "\(like ? "喜爱" : "取消喜爱")失败：\(error.localizedDescription)", isError: true))
            }
        }
    }

    private func remove(from playlist: Playlist) {
        Task {
            do {
                try await account.remove(song, from: playlist)
                onRemoved()
                showToast(Toast(message: "已从“\(playlist.title)”中删除"))
            } catch {
                showToast(Toast(message: "从“\(playlist.title)”中删除失败：\(error.localizedDescription)", isError: true))
            }
        }
    }
}

/// 列表行末尾的“…”按钮，颜色由外面的 `foregroundStyle` 决定
struct SongMenuButton: View {
    let song: Song
    var playlist: Playlist? = nil
    var onRemoved: () -> Void = {}

    var body: some View {
        Menu {
            SongMenuItems(song: song, playlist: playlist, onRemoved: onRemoved)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 28)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("更多")
        .accessibilityLabel("更多")
    }
}

/// 菜单里的“添加到歌单”选项：列出自己创建的歌单，选中就把歌加进去。
/// 成功失败都用轻提示告诉用户
struct AddToPlaylistItems: View {
    let song: Song

    @Environment(Account.self) private var account
    @Environment(\.showToast) private var showToast

    var body: some View {
        ForEach(account.createdPlaylists) { playlist in
            Button(playlist.title) { add(to: playlist) }
        }
        if account.createdPlaylists.isEmpty {
            Text("还没有创建歌单")
        }
    }

    private func add(to playlist: Playlist) {
        Task {
            do {
                try await account.add(song, to: playlist)
                showToast(Toast(message: "已添加到“\(playlist.title)”"))
            } catch {
                showToast(Toast(message: "添加到“\(playlist.title)”失败：\(error.localizedDescription)", isError: true))
            }
        }
    }
}
