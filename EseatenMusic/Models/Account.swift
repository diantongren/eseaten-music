import Foundation
import Observation

/// 网易云账号：登录状态、用户信息和侧边栏里的歌单
@Observable
@MainActor
final class Account {
    private(set) var profile: NeteaseUser?
    /// 自己创建的歌单（不含“我喜欢的音乐”）
    private(set) var createdPlaylists: [Playlist] = []
    private(set) var collectedPlaylists: [Playlist] = []
    /// “我喜欢的音乐”歌单
    private(set) var likedPlaylist: Playlist?
    /// 红心歌曲
    private(set) var likedSongIDs: Set<Song.ID> = []
    /// 启动时正在恢复登录
    private(set) var isRestoring = true

    var isLoggedIn: Bool { profile != nil }

    func playlist(_ id: Playlist.ID) -> Playlist? {
        createdPlaylists.first { $0.id == id } ?? collectedPlaylists.first { $0.id == id }
    }

    /// 启动时用保存的 Cookie 恢复登录
    func restore() async {
        defer { isRestoring = false }
        guard await NeteaseAPI.isLoggedIn else { return }
        await NeteaseAPI.refreshLogin()
        await reload()
    }

    /// 重新拉取账号和歌单；Cookie 失效时退出登录
    func reload() async {
        do {
            guard let user = try await NeteaseAPI.account() else {
                await logout()
                return
            }
            profile = user
            // 红心列表取不到不影响歌单，下次刷新再试
            async let likedIDs = try? NeteaseAPI.likedTrackIDs(uid: user.userId)
            let playlists = try await NeteaseAPI.userPlaylists(uid: user.userId)
            if let ids = await likedIDs { likedSongIDs = Set(ids.map(String.init)) }
            likedPlaylist = playlists.first(where: \.isLikedSongs).map(Catalog.playlist)
            createdPlaylists = playlists
                .filter { !$0.isLikedSongs && $0.creator?.userId == user.userId }
                .map(Catalog.playlist)
            collectedPlaylists = playlists
                .filter { $0.creator?.userId != user.userId }
                .map(Catalog.playlist)
        } catch NeteaseError.needLogin {
            await logout()
        } catch {
            // 网络问题时保留已有状态，下次再试
        }
    }

    func logout() async {
        await NeteaseAPI.logout()
        profile = nil
        createdPlaylists = []
        collectedPlaylists = []
        likedPlaylist = nil
        likedSongIDs = []
    }

    // MARK: - 专辑

    func isCollected(_ album: Album) async throws -> Bool {
        guard let id = Int(album.id) else { return false }
        return try await NeteaseAPI.isAlbumSubscribed(id: id)
    }

    func setCollected(_ album: Album, _ collected: Bool) async throws {
        guard let id = Int(album.id) else { return }
        try await NeteaseAPI.subscribe(albumID: id, collected)
    }

    // MARK: - 歌曲

    /// 红心 / 取消红心。界面先变，接口失败再改回来
    func toggleLike(_ song: Song) async throws {
        guard let id = Int(song.id) else { return }
        let like = likedSongIDs.insert(song.id).inserted
        if !like { likedSongIDs.remove(song.id) }
        do {
            try await NeteaseAPI.like(trackID: id, like)
        } catch {
            if like { likedSongIDs.remove(song.id) } else { likedSongIDs.insert(song.id) }
            throw error
        }
    }

    func add(_ song: Song, to playlist: Playlist) async throws {
        guard let id = Int(playlist.id), let songID = Int(song.id) else { return }
        try await NeteaseAPI.editPlaylist(id: id, adding: true, trackIDs: [songID])
    }

    /// 从自己创建的歌单里删歌。“我喜欢的音乐”里的歌用 `toggleLike` 取消，红心才会同步
    func remove(_ song: Song, from playlist: Playlist) async throws {
        guard let id = Int(playlist.id), let songID = Int(song.id) else { return }
        try await NeteaseAPI.editPlaylist(id: id, adding: false, trackIDs: [songID])
    }

    // MARK: - 歌单管理

    func createPlaylist(named name: String) async throws {
        try await NeteaseAPI.createPlaylist(name: name)
        await reload()
    }

    /// 自己创建的歌单删除，收藏的歌单取消收藏
    func remove(_ playlist: Playlist) async throws {
        guard let id = Int(playlist.id) else { return }
        if createdPlaylists.contains(playlist) {
            try await NeteaseAPI.deletePlaylist(id: id)
        } else {
            try await NeteaseAPI.subscribe(playlistID: id, false)
        }
        await reload()
    }

    /// “我喜欢的音乐”和自己创建的歌单
    func owns(_ playlist: Playlist) -> Bool {
        likedPlaylist?.id == playlist.id || createdPlaylists.contains { $0.id == playlist.id }
    }

    /// 收藏 / 取消收藏别人的歌单，收藏的歌单显示在侧边栏
    func setCollected(_ playlist: Playlist, _ collected: Bool) async throws {
        guard let id = Int(playlist.id) else { return }
        try await NeteaseAPI.subscribe(playlistID: id, collected)
        await reload()
    }
}
