import Foundation

// 网易云接口的返回模型。
// 同一种对象在不同接口里字段名、类型常常不一样（`ar`/`artists`、`picUrl`/`coverImgUrl`、
// `playCount` 有时是浮点数），所以解码一律宽松：取不到就用默认值，只有 id 是必需的。

// MARK: - 歌曲

struct NeteaseTrack: Decodable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let artists: [NeteaseArtistRef]
    let album: NeteaseAlbumRef
    /// 毫秒
    let durationMS: Int
    /// 别名、译名，例如“（电影《xx》主题曲）”
    let alias: [String]
    /// 0 免费 · 1 VIP · 4 付费专辑 · 8 低音质免费
    let fee: Int

    var duration: TimeInterval { TimeInterval(durationMS) / 1000 }
    var artistNames: String { artists.map(\.name).joined(separator: " / ") }

    private enum CodingKeys: String, CodingKey {
        case id, name, ar, artists, al, album, dt, duration, alia, alias, tns, fee
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = c.lenient(.name) ?? ""
        artists = c.lenient(.ar, .artists) ?? []
        album = c.lenient(.al, .album) ?? NeteaseAlbumRef(id: 0, name: "", picUrl: nil)
        durationMS = c.lenient(.dt, .duration) ?? 0
        alias = c.lenient(.tns, .alia, .alias) ?? []
        fee = c.lenient(.fee) ?? 0
    }
}

struct NeteaseArtistRef: Decodable, Hashable, Sendable {
    let id: Int
    let name: String

    private enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id) ?? 0
        name = c.lenient(.name) ?? ""
    }
}

struct NeteaseAlbumRef: Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let picUrl: String?

    init(id: Int, name: String, picUrl: String?) {
        self.id = id
        self.name = name
        self.picUrl = picUrl
    }

    private enum CodingKeys: String, CodingKey { case id, name, picUrl }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id) ?? 0
        name = c.lenient(.name) ?? ""
        picUrl = c.lenient(.picUrl)
    }
}

/// 播放地址（`song/enhance/player/url/v1`）
struct NeteaseSongURL: Decodable, Hashable, Sendable {
    let id: Int
    /// 无版权 / 需要 VIP 时为 null
    let url: String?
    let level: String?
    let type: String?
    let bitrate: Int
    /// 字节
    let size: Int
    /// 非 nil 表示只能试听这一段
    let freeTrial: FreeTrial?

    struct FreeTrial: Decodable, Hashable, Sendable {
        let start: Int?
        let end: Int?
    }

    private enum CodingKeys: String, CodingKey { case id, url, level, type, br, size, freeTrialInfo }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        url = c.lenient(.url)
        level = c.lenient(.level)
        type = c.lenient(.type)
        bitrate = c.lenient(.br) ?? 0
        size = c.lenient(.size) ?? 0
        freeTrial = c.lenient(.freeTrialInfo)
    }
}

/// 歌词：`lrc` 原文，`tlyric` 翻译，`romalrc` 罗马音，`yrc` 逐字歌词（只有 v1 接口返回）
struct NeteaseLyric: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let lyric: String?
    }

    let lrc: Body?
    let tlyric: Body?
    let romalrc: Body?
    let yrc: Body?
    let nolyric: Bool?
    let uncollected: Bool?
}

// MARK: - 歌单

struct NeteasePlaylist: Decodable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let coverURL: String?
    let creator: NeteaseUser?
    let description: String?
    /// 推荐语（个性化推荐接口才有）
    let copywriter: String?
    let trackCount: Int
    let playCount: Int
    /// 5 = “我喜欢的音乐”
    let specialType: Int
    let subscribed: Bool
    /// 排行榜才有，例如“每天更新”
    let updateFrequency: String?
    /// 歌单详情才有：完整的歌曲 id 列表
    let trackIDs: [Int]
    /// 歌单详情才有：歌曲，未登录时可能只返回前几首
    let tracks: [NeteaseTrack]

    var isLikedSongs: Bool { specialType == 5 }

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl, coverImgUrl, creator, description, copywriter
        case trackCount, playCount, playcount, specialType, subscribed, updateFrequency, tracks, trackIds
    }

    private struct IDRef: Decodable { let id: Int }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = c.lenient(.name) ?? ""
        coverURL = c.lenient(.coverImgUrl, .picUrl)
        creator = c.lenient(.creator)
        description = c.lenient(.description)
        copywriter = c.lenient(.copywriter)
        trackCount = c.lenient(.trackCount) ?? 0
        playCount = Int(c.lenient(.playCount, .playcount) ?? 0.0)
        specialType = c.lenient(.specialType) ?? 0
        subscribed = c.lenient(.subscribed) ?? false
        updateFrequency = c.lenient(.updateFrequency)
        trackIDs = (c.lenient(.trackIds) as [IDRef]?)?.map(\.id) ?? []
        tracks = c.lenient(.tracks) ?? []
    }
}

// MARK: - 专辑 / 艺人 / 用户

struct NeteaseAlbum: Decodable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let artistName: String
    /// 第一位艺人，用来跳转艺人页、加载“更多作品”
    let primaryArtist: NeteaseArtistRef?
    /// 毫秒时间戳
    let publishTime: Int
    let size: Int
    /// “专辑”“EP/Single”“录音室版”等
    let type: String?
    let company: String?
    let description: String?

    var publishDate: Date? {
        publishTime > 0 ? Date(timeIntervalSince1970: TimeInterval(publishTime) / 1000) : nil
    }

    var year: Int {
        publishDate.map { Calendar.current.component(.year, from: $0) } ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl, artist, artists, publishTime, size, subType, type, company, description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = c.lenient(.name) ?? ""
        picUrl = c.lenient(.picUrl)
        let artists: [NeteaseArtistRef] = c.lenient(.artists) ?? []
        let artist: NeteaseArtistRef? = c.lenient(.artist)
        artistName = artists.isEmpty ? (artist?.name ?? "") : artists.map(\.name).joined(separator: " / ")
        primaryArtist = (artists.first ?? artist).flatMap { $0.id > 0 ? $0 : nil }
        publishTime = c.lenient(.publishTime) ?? 0
        size = c.lenient(.size) ?? 0
        type = c.lenient(.subType, .type)
        company = c.lenient(.company)
        description = c.lenient(.description)
    }
}

struct NeteaseArtist: Decodable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let albumSize: Int
    let musicSize: Int
    let briefDesc: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl, img1v1Url, cover, avatar, albumSize, musicSize, briefDesc
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = c.lenient(.name) ?? ""
        picUrl = c.lenient(.picUrl, .cover, .avatar, .img1v1Url)
        albumSize = c.lenient(.albumSize) ?? 0
        musicSize = c.lenient(.musicSize) ?? 0
        briefDesc = c.lenient(.briefDesc)
    }
}

struct NeteaseUser: Decodable, Hashable, Sendable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?
    /// 0 普通用户，大于 0 为 VIP（11 黑胶 VIP，110 等为黑胶 SVIP）
    let vipType: Int

    private enum CodingKeys: String, CodingKey { case userId, nickname, avatarUrl, vipType }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = c.lenient(.userId) ?? 0
        nickname = c.lenient(.nickname) ?? ""
        avatarUrl = c.lenient(.avatarUrl)
        vipType = c.lenient(.vipType) ?? 0
    }
}

// MARK: - 解码工具

extension KeyedDecodingContainer {
    /// 依次尝试这些键，返回第一个能解出来的值；类型对不上也当作没有
    func lenient<T: Decodable>(_ keys: Key...) -> T? {
        for key in keys {
            if let value = try? decodeIfPresent(T.self, forKey: key) { return value }
        }
        return nil
    }
}

extension URL {
    /// 网易云返回的图片、音频地址常是 http，统一换成 https
    static func netease(_ string: String?) -> URL? {
        guard let string, !string.isEmpty, var components = URLComponents(string: string) else { return nil }
        if components.scheme == "http" { components.scheme = "https" }
        return components.url
    }

    /// 网易云图片 CDN 支持 `?param=宽y高` 返回缩略图。按显示尺寸取合适的一档，非网易云图片原样返回
    func neteaseThumbnail(points: CGFloat) -> URL {
        guard host()?.hasSuffix(".music.126.net") == true else { return self }
        let pixels = [100, 200, 400, 800].first { CGFloat($0) >= points * 2 } ?? 1000
        return appending(queryItems: [URLQueryItem(name: "param", value: "\(pixels)y\(pixels)")])
    }
}
