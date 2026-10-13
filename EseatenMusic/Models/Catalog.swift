import Foundation

/// 界面的数据源：调用网易云接口，把结果转换成 `Song` / `Album` / `Playlist` / `Artist`
enum Catalog {
    // MARK: - 首页 / 新发现 / 广播

    struct Home: Sendable {
        /// “置顶精选”：登录后第一张是每日推荐，后面是官方榜单
        var topPicks: [Playlist]
        var playlists: [Playlist]
        /// 新歌所在的专辑
        var newSongAlbums: [Album]
    }

    static func home(loggedIn: Bool) async throws -> Home {
        async let toplists = NeteaseAPI.toplists()
        async let recommended = recommendedPlaylists(loggedIn: loggedIn)
        async let newSongs = NeteaseAPI.newSongs(limit: 12)
        async let daily = loggedIn ? try? dailyPlaylist() : nil

        var picks = try await toplists.prefix(4).map(playlist)
        if let daily = await daily, !daily.songs.isEmpty { picks.insert(daily, at: 0) }
        var seen = Set<Int>()
        let albums = try await newSongs
            .filter { $0.album.id > 0 && seen.insert($0.album.id).inserted }
            .map { Album(id: String($0.album.id), title: $0.album.name, artist: $0.artistNames,
                         genre: "", year: 0, songs: [], artworkURL: .netease($0.album.picUrl)) }
        return try await Home(topPicks: picks, playlists: recommended, newSongAlbums: albums)
    }

    struct Discover: Sendable {
        var newAlbums: [Album]
        var hotPlaylists: [Playlist]
        var highQualityPlaylists: [Playlist]
    }

    static func discover() async throws -> Discover {
        async let albums = NeteaseAPI.newAlbums(limit: 20)
        async let hot = NeteaseAPI.topPlaylists(limit: 20)
        async let quality = NeteaseAPI.highQualityPlaylists(limit: 20)
        return try await Discover(newAlbums: albums.map(album), hotPlaylists: hot.map(playlist),
                                  highQualityPlaylists: quality.map(playlist))
    }

    static func toplists() async throws -> [Playlist] {
        try await NeteaseAPI.toplists().map(playlist)
    }

    /// 私人漫游，每次几首，播完再取
    static func personalFM() async throws -> [Song] {
        try await NeteaseAPI.personalFM().map(song)
    }

    private static func recommendedPlaylists(loggedIn: Bool) async throws -> [Playlist] {
        if loggedIn, let daily = try? await NeteaseAPI.dailyPlaylists(), !daily.isEmpty {
            return daily.map(playlist)
        }
        return try await NeteaseAPI.personalizedPlaylists().map(playlist)
    }

    /// 每日推荐歌曲包装成一个播放列表；不给封面图，用渐变 + 标题
    static func dailyPlaylist() async throws -> Playlist {
        let songs = try await NeteaseAPI.dailySongs().map(song)
        var seen = Set<String>()
        let artists = songs.map(\.artist).filter { seen.insert($0).inserted }.prefix(3)
        return Playlist(id: "daily", title: "每日推荐", curator: "根据你的收听记录每日更新",
                        songs: songs, blurb: artists.joined(separator: "、"))
    }

    // MARK: - 详情

    /// 专辑 / 歌单的歌曲；已经带着歌曲的（比如每日推荐）直接返回
    static func songs(in destination: Destination) async throws -> [Song] {
        switch destination {
        case .playlist(let playlist):
            guard playlist.songs.isEmpty, let id = Int(playlist.id) else { return playlist.songs }
            return try await playlistSongs(id: id)
        case .album(let album):
            guard album.songs.isEmpty, let id = Int(album.id) else { return album.songs }
            return try await NeteaseAPI.album(id: id).songs.map(song)
        case .artist(let artist):
            guard let id = Int(artist.id) else { return [] }
            return try await NeteaseAPI.artist(id: id).hotSongs.map(song)
        }
    }

    /// 详情页的内容：歌曲之外还有简介，专辑另有发行信息
    struct CollectionDetail: Sendable {
        var songs: [Song]
        /// 专辑介绍 / 歌单描述
        var description: String?
        /// 专辑的类型 · 年份。列表接口给的专辑常缺这两项，以详情为准
        var caption: String?
        var releaseDate: Date?
        var company: String?
        /// 专辑的艺人，用来加载“更多 xx 的作品”
        var artist: Artist?
    }

    static func detail(of destination: Destination) async throws -> CollectionDetail {
        switch destination {
        case .playlist(let playlist):
            guard playlist.songs.isEmpty, let id = Int(playlist.id) else { return CollectionDetail(songs: playlist.songs) }
            let detail = try await NeteaseAPI.playlist(id: id)
            return CollectionDetail(songs: try await songs(of: detail), description: detail.description)
        case .album(let album):
            guard album.songs.isEmpty, let id = Int(album.id) else { return CollectionDetail(songs: album.songs) }
            let (info, tracks) = try await NeteaseAPI.album(id: id)
            return CollectionDetail(
                songs: tracks.map(song), description: info.description, caption: self.album(info).caption,
                releaseDate: info.publishDate, company: info.company,
                artist: info.primaryArtist.map { Artist(id: String($0.id), name: $0.name) }
            )
        case .artist:
            return CollectionDetail(songs: try await songs(in: destination))
        }
    }

    /// 艺人的专辑，按热度排
    static func albums(by artist: Artist, limit: Int = 30) async throws -> [Album] {
        guard let id = Int(artist.id) else { return [] }
        return try await NeteaseAPI.artistAlbums(id: id, limit: limit).map(album)
    }

    static func playlistSongs(id: Int) async throws -> [Song] {
        try await songs(of: NeteaseAPI.playlist(id: id))
    }

    /// 歌单详情只保证 `trackIds` 完整，缺的歌曲分批用 song/detail 补齐，再按原顺序排好
    private static func songs(of detail: NeteasePlaylist) async throws -> [Song] {
        var tracks = detail.tracks
        let loaded = Set(tracks.map(\.id))
        let missing = detail.trackIDs.filter { !loaded.contains($0) }
        for start in stride(from: 0, to: missing.count, by: 500) {
            tracks += try await NeteaseAPI.songDetails(ids: Array(missing[start..<min(start + 500, missing.count)]))
        }
        if !detail.trackIDs.isEmpty {
            let byID = Dictionary(tracks.map { ($0.id, $0) }) { first, _ in first }
            tracks = detail.trackIDs.compactMap { byID[$0] }
        }
        return tracks.map(song)
    }

    struct ArtistPage: Sendable {
        var artist: Artist
        var songs: [Song]
        var albums: [Album]
    }

    static func artistPage(_ artist: Artist) async throws -> ArtistPage {
        guard let id = Int(artist.id) else { return ArtistPage(artist: artist, songs: [], albums: []) }
        async let info = NeteaseAPI.artist(id: id)
        async let albums = NeteaseAPI.artistAlbums(id: id, limit: 50)
        let (detail, hotSongs) = try await info
        return try await ArtistPage(artist: self.artist(detail), songs: hotSongs.map(song), albums: albums.map(album))
    }

    static func search(_ keyword: String, scope: SearchModel.Scope) async throws -> SearchModel.Results {
        switch scope {
        case .songs:
            .songs(try await NeteaseAPI.search(keyword, type: .songs, limit: 60).songs?.map(song) ?? [])
        case .albums:
            .albums(try await NeteaseAPI.search(keyword, type: .albums, limit: 60).albums?.map(album) ?? [])
        case .artists:
            .artists(try await NeteaseAPI.search(keyword, type: .artists, limit: 60).artists?.map(artist) ?? [])
        case .playlists:
            .playlists(try await NeteaseAPI.search(keyword, type: .playlists, limit: 60).playlists?.map(playlist) ?? [])
        }
    }

    // MARK: - 资料库（需要登录）

    static func recentSongs() async throws -> [Song] {
        try await NeteaseAPI.recentSongs().map(song)
    }

    static func cloudSongs() async throws -> [Song] {
        try await NeteaseAPI.cloudSongs().map(song)
    }

    static func likedAlbums() async throws -> [Album] {
        try await NeteaseAPI.likedAlbums().map(album)
    }

    static func likedArtists() async throws -> [Artist] {
        try await NeteaseAPI.likedArtists().map(artist)
    }

    // MARK: - 播放

    struct Stream: Sendable {
        let url: URL
        /// 只能试听时片段的长度（未登录或非 VIP 播放 VIP 歌曲），完整播放为 nil
        let trialLength: TimeInterval?
    }

    /// 歌词：同一首歌只请求一次
    @MainActor private static var lyricsCache: [Song.ID: Lyrics] = [:]

    @MainActor
    static func lyrics(for song: Song) async throws -> Lyrics {
        if let cached = lyricsCache[song.id] { return cached }
        guard let id = Int(song.id) else { return Lyrics(status: .unavailable) }
        let lyrics = Lyrics(try await NeteaseAPI.lyric(id: id))
        lyricsCache[song.id] = lyrics
        return lyrics
    }

    static func stream(for song: Song) async throws -> Stream {
        guard let id = Int(song.id) else { throw NeteaseError.unavailable }
        guard let data = try await NeteaseAPI.songURLs(ids: [id]).first,
              let url = URL.netease(data.url) else { throw NeteaseError.unavailable }
        let trial = data.freeTrial.map { TimeInterval(($0.end ?? 0) - ($0.start ?? 0)) }
        return Stream(url: url, trialLength: trial.map { $0 > 0 ? $0 : 30 })
    }

    // MARK: - 转换

    static func song(_ track: NeteaseTrack) -> Song {
        Song(id: String(track.id), title: track.name, artist: track.artistNames, album: track.album.name,
             duration: track.duration, artworkSeed: StableHash.of(String(track.album.id)),
             artworkURL: .netease(track.album.picUrl),
             artists: track.artists.filter { $0.id > 0 }.map { Artist(id: String($0.id), name: $0.name) })
    }

    static func playlist(_ playlist: NeteasePlaylist) -> Playlist {
        Playlist(
            id: String(playlist.id), title: playlist.name,
            curator: playlist.creator?.nickname ?? playlist.updateFrequency ?? "网易云音乐",
            songs: [], artworkURL: .netease(playlist.coverURL),
            trackCount: playlist.trackCount > 0 ? playlist.trackCount : nil,
            blurb: [playlist.copywriter, playlist.description].compactMap { $0 }.first { !$0.isEmpty }
        )
    }

    static func album(_ album: NeteaseAlbum) -> Album {
        Album(id: String(album.id), title: album.name, artist: album.artistName, genre: album.type ?? "",
              year: album.year, songs: [], artworkURL: .netease(album.picUrl))
    }

    static func artist(_ artist: NeteaseArtist) -> Artist {
        Artist(id: String(artist.id), name: artist.name, artworkURL: .netease(artist.picUrl))
    }
}
