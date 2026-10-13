import Foundation

struct Song: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkSeed: Int
    var artworkURL: URL? = nil
    /// 每位艺人，用来跳转艺人页；`artist` 是拼好的显示名
    var artists: [Artist] = []
}

/// 专辑和播放列表共用的详情页数据
protocol TrackCollection: Identifiable, Hashable where ID == String {
    var title: String { get }
    var subtitle: String { get }
    var caption: String { get }
    var artworkSeed: Int { get }
    /// 真实封面；为 nil 时用种子生成的渐变代替
    var artworkURL: URL? { get }
    /// 播放列表封面上印的文字，专辑为 nil
    var artworkLabel: String? { get }
    var songs: [Song] { get }
    var destination: Destination { get }
}

struct Album: TrackCollection, Sendable {
    let id: String
    let title: String
    let artist: String
    let genre: String
    let year: Int
    /// 网易云专辑在打开详情页前为空，由详情页加载
    var songs: [Song]
    var artworkURL: URL? = nil

    var subtitle: String { artist }
    var caption: String {
        [genre, year > 0 ? String(year) : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var artworkSeed: Int { StableHash.of(id) }
    var artworkLabel: String? { nil }
    var destination: Destination { .album(self) }
}

struct Playlist: TrackCollection, Sendable {
    let id: String
    let title: String
    let curator: String
    /// 网易云歌单在打开详情页前为空，由详情页加载
    var songs: [Song]
    var artworkURL: URL? = nil
    /// 打开详情前只知道歌曲数量
    var trackCount: Int? = nil
    /// 一句话简介：推荐语、榜单说明等
    var blurb: String? = nil

    var subtitle: String { curator }
    var caption: String { "\(trackCount ?? songs.count) 首歌曲" }
    var artworkSeed: Int { StableHash.of(id) }
    var artworkLabel: String? { title }
    var destination: Destination { .playlist(self) }
}

struct Artist: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var artworkURL: URL? = nil
    var artworkSeed: Int { StableHash.of(name) }
}

enum SidebarItem: Hashable {
    case search, home, explore, radio
    case likedSongs, daily, recents, collections, cloud
    case playlist(Playlist.ID)
}

/// 跨启动稳定的字符串哈希（`hashValue` 每次启动都会变）
enum StableHash {
    static func of(_ string: String) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Int(hash % 1_000_003)
    }
}

extension TimeInterval {
    var mmss: String {
        let seconds = Int(self.rounded(.down))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
