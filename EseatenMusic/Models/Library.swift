import Foundation

/// 演示用的静态曲库，只给 SwiftUI 预览用；实际数据来自网易云（见 `Catalog`）
enum Library {
    static let albums: [Album] = [
        album("nightflight", "夜航星", "北岸乐队", "另类摇滚", 2026,
              ["夜航星", "灯塔", "退潮", "无人区", "北纬三十度", "归航"]),
        album("neon-tides", "Neon Tides", "Neon Harbor", "电子", 2025,
              ["Neon Tides", "Afterglow", "Static Hearts", "Low Orbit", "Midnight Drive", "Signal"]),
        album("fog-island", "雾岛来信", "雾岛", "民谣", 2026,
              ["雾岛来信", "青苔", "旧邮局", "慢车", "晚风知道"]),
        album("golden-hour", "Golden Hour Sessions", "Mira Vale", "R&B", 2025,
              ["Golden Hour", "Velvet", "Slow Burn", "Honey", "Linger"]),
        album("city-wanderer", "城市漫游者", "陈屿", "流行", 2026,
              ["城市漫游者", "地铁末班", "霓虹之下", "第七街", "天台"]),
        album("paper-moons", "Paper Moons", "The Lanterns", "独立流行", 2024,
              ["Paper Moons", "Kite Strings", "Summer Static", "Orchard"]),
        album("weightless", "失重", "白昼计划", "后摇", 2025,
              ["失重", "引力", "漂浮", "星尘", "回声室"]),
        album("blue-monday", "Blue Monday Club", "Oscar Lind Trio", "爵士", 2024,
              ["Blue Monday", "Smoke Rings", "After Hours", "Rainy Avenue"]),
        album("shanhai", "山海经", "青鸟", "国风", 2026,
              ["山海经", "昆仑", "精卫", "九尾", "扶桑"]),
        album("pulse", "Pulse", "KIRA", "舞曲", 2026,
              ["Pulse", "Higher", "Run It Back", "Lights Out"]),
    ]

    static let songs: [Song] = albums.flatMap(\.songs)

    static let artists: [Artist] = Set(albums.map(\.artist)).sorted().map { Artist(id: $0, name: $0) }

    /// 侧边栏里的“我的”播放列表
    static let playlists: [Playlist] = [
        playlist("favorites", "我的最爱", "我"),
        playlist("late-night", "深夜循环", "我"),
        playlist("commute", "通勤节奏", "我"),
    ]

    /// 首页推荐的编辑精选
    static let featuredPlaylists: [Playlist] = [
        playlist("today", "今日推荐", "Eseaten Music"),
        playlist("cn-new", "华语新歌", "Eseaten Music"),
        playlist("electronic", "电子精选", "Eseaten Music"),
        playlist("chill", "放松时刻", "Eseaten Music"),
        playlist("focus", "专注时刻", "Eseaten Music"),
        playlist("party", "周末派对", "Eseaten Music"),
    ]

    static var recentlyAdded: [Album] { albums.sorted { $0.year > $1.year } }

    static func playlist(_ id: Playlist.ID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    static func albums(by artist: Artist) -> [Album] {
        albums.filter { $0.artist == artist.name }
    }

    static func search(_ text: String) -> [Song] {
        songs.filter {
            $0.title.localizedCaseInsensitiveContains(text)
                || $0.artist.localizedCaseInsensitiveContains(text)
                || $0.album.localizedCaseInsensitiveContains(text)
        }
    }

    // MARK: - 构造

    private static func album(
        _ id: String, _ title: String, _ artist: String, _ genre: String, _ year: Int, _ tracks: [String]
    ) -> Album {
        let seed = StableHash.of(id)
        let songs = tracks.enumerated().map { index, name in
            let songID = "\(id)-\(index)"
            return Song(
                id: songID, title: name, artist: artist, album: title,
                duration: TimeInterval(150 + StableHash.of(songID) % 150),
                artworkSeed: seed
            )
        }
        return Album(id: id, title: title, artist: artist, genre: genre, year: year, songs: songs)
    }

    /// 按 id 从曲库里确定性地挑歌
    private static func playlist(_ id: String, _ title: String, _ curator: String) -> Playlist {
        let picked = songs.filter { StableHash.of($0.id + id) % 3 == 0 }.prefix(14)
        return Playlist(id: id, title: title, curator: curator, songs: Array(picked))
    }
}
