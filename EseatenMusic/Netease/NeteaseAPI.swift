import Foundation

/// 网易云接口。路径前缀 `/weapi` 或 `/eapi` 由 `NeteaseClient` 补上，
/// 两种加密下同一个接口的内部路径都是 `/api{path}`。
enum NeteaseAPI {
    private static var client: NeteaseClient { .shared }

    // MARK: - 登录

    /// 二维码登录第一步：取 unikey，二维码内容是 `qrContent(for:)`
    static func qrKey() async throws -> String {
        struct Response: Decodable { let unikey: String }
        return try await weapi(Response.self, "/login/qrcode/unikey", ["type": 1]).unikey
    }

    static func qrContent(for key: String) -> String {
        "https://music.163.com/login?codekey=\(key)"
    }

    enum QRStatus: Sendable, Equatable {
        case expired
        case waiting
        /// 已扫码，等待手机上确认
        case scanned(nickname: String?)
        case authorized
    }

    /// 轮询扫码状态：800 过期 · 801 等待扫码 · 802 待确认 · 803 成功（登录 Cookie 随 Set-Cookie 返回）
    static func qrCheck(key: String) async throws -> QRStatus {
        struct Response: Decodable {
            let code: Int
            let message: String?
            let nickname: String?
            let cookie: String?
        }
        let data = try await client.weapi("/login/qrcode/client/login", ["key": key, "type": 1])
        let response = try JSONDecoder().decode(Response.self, from: data)
        switch response.code {
        case 800: return .expired
        case 801: return .waiting
        case 802: return .scanned(nickname: response.nickname)
        case 803:
            if let cookie = response.cookie { await client.absorbCookieString(cookie) }
            return .authorized
        default: throw NeteaseError.api(code: response.code, message: response.message)
        }
    }

    /// 给手机号发短信验证码
    static func sendSMSCode(phone: String, countryCode: String = "86") async throws {
        _ = try await weapi(CodeOnly.self, "/sms/captcha/sent",
                            ["cellphone": phone, "ctcode": countryCode, "secrete": "music_middleuser_pclogin"])
    }

    /// 手机号 + 验证码登录，登录 Cookie 随 Set-Cookie 返回
    static func loginWithSMS(phone: String, code: String, countryCode: String = "86") async throws {
        _ = try await weapi(CodeOnly.self, "/w/login/cellphone",
                            ["phone": phone, "countrycode": countryCode, "captcha": code,
                             "remember": "true", "https": "true", "type": "1"])
    }

    /// 续期登录 Cookie，启动时调用一次
    static func refreshLogin() async {
        _ = try? await client.weapi("/login/token/refresh")
    }

    static func logout() async {
        _ = try? await client.weapi("/logout")
        await client.clearLogin()
    }

    static var isLoggedIn: Bool {
        get async { await client.isLoggedIn }
    }

    /// 当前账号；未登录时 profile 为 null
    static func account() async throws -> NeteaseUser? {
        struct Response: Decodable { let profile: NeteaseUser? }
        return try await weapi(Response.self, "/w/nuser/account/get").profile
    }

    // MARK: - 用户资料库（需要登录）

    /// 创建和收藏的歌单，第一个是“我喜欢的音乐”
    static func userPlaylists(uid: Int, limit: Int = 1000, offset: Int = 0) async throws -> [NeteasePlaylist] {
        struct Response: Decodable { let playlist: [NeteasePlaylist] }
        return try await weapi(Response.self, "/user/playlist",
                               ["uid": uid, "limit": limit, "offset": offset, "includeVideo": true]).playlist
    }

    /// 红心歌曲的 id
    static func likedTrackIDs(uid: Int) async throws -> [Int] {
        struct Response: Decodable { let ids: [Int] }
        return try await weapi(Response.self, "/song/like/get", ["uid": uid]).ids
    }

    /// 红心 / 取消红心。走 eapi：网页端的 weapi 版本会被风控拦下，返回 -460“网络环境存在风险”
    static func like(trackID: Int, _ like: Bool) async throws {
        _ = try await eapi(CodeOnly.self, "/radio/like",
                           ["alg": "itembased", "trackId": trackID, "like": like, "time": "3"])
    }

    static func likedAlbums(limit: Int = 500, offset: Int = 0) async throws -> [NeteaseAlbum] {
        try await weapi(DataList<NeteaseAlbum>.self, "/album/sublist",
                        ["limit": limit, "offset": offset, "total": true]).data
    }

    static func likedArtists(limit: Int = 500, offset: Int = 0) async throws -> [NeteaseArtist] {
        try await weapi(DataList<NeteaseArtist>.self, "/artist/sublist",
                        ["limit": limit, "offset": offset, "total": true]).data
    }

    /// 听歌排行：`week` 为 true 取最近一周，否则取所有时间
    static func playRecords(uid: Int, week: Bool) async throws -> [NeteaseTrack] {
        struct Item: Decodable { let song: NeteaseTrack }
        struct Response: Decodable { let weekData: [Item]?; let allData: [Item]? }
        let response = try await weapi(Response.self, "/v1/play/record", ["uid": uid, "type": week ? 1 : 0])
        return ((week ? response.weekData : response.allData) ?? []).map(\.song)
    }

    /// 最近播放的歌曲（按时间倒序，最多 300 首）
    static func recentSongs(limit: Int = 300) async throws -> [NeteaseTrack] {
        struct Item: Decodable { let data: NeteaseTrack? }
        struct Body: Decodable { let list: [Item] }
        struct Response: Decodable { let data: Body? }
        return try await weapi(Response.self, "/play-record/song/list", ["limit": limit])
            .data?.list.compactMap(\.data) ?? []
    }

    /// 云盘歌曲
    static func cloudSongs(limit: Int = 500, offset: Int = 0) async throws -> [NeteaseTrack] {
        struct Item: Decodable { let simpleSong: NeteaseTrack? }
        return try await weapi(DataList<Item>.self, "/v1/cloud/get", ["limit": limit, "offset": offset])
            .data.compactMap(\.simpleSong)
    }

    static func deleteCloudSong(id: Int) async throws {
        _ = try await weapi(CodeOnly.self, "/cloud/del", ["songIds": "[\(id)]"])
    }

    /// 听歌上报。`startplay` 写入“最近播放”，`play` 累加听歌排行，两条都要发
    static func scrobbleStart(trackID: Int, sourceID: Int) async {
        await weblog(["action": "startplay",
                      "json": ["id": trackID, "type": "song", "mainsite": "1",
                               "content": "id=\(sourceID)"] as [String: any Sendable]])
    }

    static func scrobbleEnd(trackID: Int, sourceID: Int, seconds: Int) async {
        await weblog(["action": "play",
                      "json": ["id": trackID, "type": "song", "sourceId": String(sourceID), "time": seconds,
                               "end": "playend", "source": "list", "wifi": 0, "download": 0,
                               "mainsite": "1", "content": "id=\(sourceID)"] as [String: any Sendable]])
    }

    private static func weblog(_ entry: [String: any Sendable]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: [entry as [String: Any]]) else { return }
        // 上报接口按桌面客户端的身份发（os=osx）
        _ = try? await client.eapi("/feedback/weblog", ["logs": String(decoding: data, as: UTF8.self)],
                                   cookieOverrides: ["os": "osx"])
    }

    // MARK: - 推荐

    /// 推荐歌单（不需要登录）
    static func personalizedPlaylists(limit: Int = 30) async throws -> [NeteasePlaylist] {
        struct Response: Decodable { let result: [NeteasePlaylist] }
        return try await weapi(Response.self, "/personalized/playlist",
                               ["limit": limit, "total": true, "n": 1000]).result
    }

    /// 每日推荐歌单（需要登录）
    static func dailyPlaylists() async throws -> [NeteasePlaylist] {
        struct Response: Decodable { let recommend: [NeteasePlaylist] }
        return try await weapi(Response.self, "/v1/discovery/recommend/resource").recommend
    }

    /// 每日推荐歌曲（需要登录；新账号没有听歌记录时 data 为 null）
    static func dailySongs() async throws -> [NeteaseTrack] {
        struct Body: Decodable { let dailySongs: [NeteaseTrack]? }
        struct Response: Decodable { let data: Body? }
        return try await weapi(Response.self, "/v3/discovery/recommend/songs").data?.dailySongs ?? []
    }

    /// 每日推荐里点“不喜欢”，返回一首替换的歌
    static func dislikeDailySong(id: Int) async throws -> NeteaseTrack {
        struct Response: Decodable { let data: NeteaseTrack }
        return try await weapi(Response.self, "/v2/discovery/recommend/dislike",
                               ["resId": id, "resType": 4, "sceneType": 1]).data
    }

    /// 推荐新歌（不需要登录）
    static func newSongs(limit: Int = 12) async throws -> [NeteaseTrack] {
        struct Item: Decodable { let song: NeteaseTrack? }
        struct Response: Decodable { let result: [Item] }
        return try await weapi(Response.self, "/personalized/newsong",
                               ["type": "recommend", "limit": limit, "areaId": 0]).result.compactMap(\.song)
    }

    /// 私人漫游（FM），每次返回几首
    static func personalFM() async throws -> [NeteaseTrack] {
        struct Response: Decodable { let data: [NeteaseTrack]? }
        return try await weapi(Response.self, "/v1/radio/get").data ?? []
    }

    /// FM 里点“不喜欢”
    static func trashFM(trackID: Int) async throws {
        _ = try await weapi(CodeOnly.self, "/radio/trash/add?alg=RT&songId=\(trackID)&time=25", ["songId": trackID])
    }

    /// 心动模式：以某首歌为种子，从歌单生成播放队列
    static func heartbeat(trackID: Int, playlistID: Int) async throws -> [NeteaseTrack] {
        struct Item: Decodable { let songInfo: NeteaseTrack? }
        struct Response: Decodable { let data: [Item]? }
        return try await weapi(Response.self, "/playmode/intelligence/list",
                               ["songId": trackID, "playlistId": playlistID, "startMusicId": trackID,
                                "type": "fromPlayOne", "count": 1]).data?.compactMap(\.songInfo) ?? []
    }

    static func similarSongs(trackID: Int, limit: Int = 30) async throws -> [NeteaseTrack] {
        struct Response: Decodable { let songs: [NeteaseTrack] }
        return try await weapi(Response.self, "/v1/discovery/simiSong",
                               ["songid": trackID, "limit": limit, "offset": 0]).songs
    }

    // MARK: - 歌单

    /// 歌单详情。`trackIDs` 是完整的，`tracks` 未登录时可能不全，缺的用 `songDetails` 补
    static func playlist(id: Int) async throws -> NeteasePlaylist {
        struct Response: Decodable { let playlist: NeteasePlaylist }
        return try await weapi(Response.self, "/v6/playlist/detail", ["id": id, "n": 100_000, "s": 8]).playlist
    }

    /// 按 id 批量取歌曲详情
    static func songDetails(ids: [Int]) async throws -> [NeteaseTrack] {
        guard !ids.isEmpty else { return [] }
        struct Response: Decodable { let songs: [NeteaseTrack] }
        let c = "[" + ids.map { "{\"id\":\($0)}" }.joined(separator: ",") + "]"
        return try await weapi(Response.self, "/v3/song/detail", ["c": c]).songs
    }

    /// 歌单广场，`order` 为 hot 或 new
    static func topPlaylists(category: String = "全部", order: String = "hot",
                             limit: Int = 30, offset: Int = 0) async throws -> [NeteasePlaylist] {
        struct Response: Decodable { let playlists: [NeteasePlaylist] }
        return try await weapi(Response.self, "/playlist/list",
                               ["cat": category, "order": order, "limit": limit, "offset": offset, "total": true]).playlists
    }

    /// 精品歌单，翻页用上一页最后一个的 updateTime 作为 `before`
    static func highQualityPlaylists(category: String = "全部", limit: Int = 30, before: Int = 0) async throws -> [NeteasePlaylist] {
        struct Response: Decodable { let playlists: [NeteasePlaylist] }
        return try await weapi(Response.self, "/playlist/highquality/list",
                               ["cat": category, "limit": limit, "lasttime": before, "total": true]).playlists
    }

    /// 所有排行榜
    static func toplists() async throws -> [NeteasePlaylist] {
        struct Response: Decodable { let list: [NeteasePlaylist] }
        return try await eapi(Response.self, "/toplist").list
    }

    @discardableResult
    static func createPlaylist(name: String, isPrivate: Bool = false) async throws -> Int? {
        struct Response: Decodable { let id: Int? }
        return try await weapi(Response.self, "/playlist/create",
                               ["name": name, "privacy": isPrivate ? 10 : 0, "type": "NORMAL"]).id
    }

    static func deletePlaylist(id: Int) async throws {
        _ = try await weapi(CodeOnly.self, "/playlist/remove", ["ids": "[\(id)]"])
    }

    static func subscribe(playlistID: Int, _ subscribe: Bool) async throws {
        _ = try await weapi(CodeOnly.self, "/playlist/\(subscribe ? "subscribe" : "unsubscribe")", ["id": playlistID])
    }

    /// 往歌单里加歌 / 删歌
    static func editPlaylist(id: Int, adding: Bool, trackIDs: [Int]) async throws {
        func send(_ ids: [Int]) async throws -> Data {
            try await client.weapi("/playlist/manipulate/tracks",
                                   ["op": adding ? "add" : "del", "pid": id, "imme": "true",
                                    "trackIds": "[" + ids.map(String.init).joined(separator: ",") + "]"])
        }
        let data = try await send(trackIDs)
        // 已知的怪癖：加歌偶尔返回 512，把 id 列表重复一遍再发就能成功
        if adding, (try? JSONDecoder().decode(CodeOnly.self, from: data))?.code == 512 {
            try check(try await send(trackIDs + trackIDs))
        } else {
            try check(data)
        }
    }

    // MARK: - 歌曲

    /// 音质 level：standard · higher · exhigh（极高）· lossless · hires · jyeffect（高清环绕声）· sky（沉浸环绕声）· jymaster（超清母带）
    static func songURLs(ids: [Int], level: String = "exhigh") async throws -> [NeteaseSongURL] {
        struct Response: Decodable { let data: [NeteaseSongURL] }
        var payload: [String: any Sendable] = ["ids": "[" + ids.map(String.init).joined(separator: ",") + "]",
                                               "level": level, "encodeType": "flac"]
        if level == "sky" { payload["immerseType"] = "c51" }
        return try await eapi(Response.self, "/song/enhance/player/url/v1", payload).data
    }

    /// 下载地址，和播放地址分开判断权限
    static func downloadURL(id: Int, level: String = "lossless") async throws -> NeteaseSongURL? {
        struct Response: Decodable { let data: NeteaseSongURL? }
        return try await eapi(Response.self, "/song/enhance/download/url/v1",
                              ["id": id, "level": level, "immerseType": "c51"]).data
    }

    /// 歌词。先用带逐字歌词的 v1 接口，拿不到再退回老接口
    static func lyric(id: Int) async throws -> NeteaseLyric {
        if let lyric = try? await weapi(NeteaseLyric.self, "/song/lyric/v1",
                                        ["id": id, "cp": false, "lv": 0, "kv": 0, "tv": 0, "rv": 0,
                                         "yv": 0, "ytv": 0, "yrv": 0]),
           lyric.lrc?.lyric?.isEmpty == false || lyric.yrc?.lyric?.isEmpty == false {
            return lyric
        }
        return try await weapi(NeteaseLyric.self, "/song/lyric", ["id": id, "lv": -1, "kv": -1, "tv": -1, "rv": -1])
    }

    // MARK: - 专辑

    static func album(id: Int) async throws -> (album: NeteaseAlbum, songs: [NeteaseTrack]) {
        struct Response: Decodable { let album: NeteaseAlbum; let songs: [NeteaseTrack] }
        let response = try await weapi(Response.self, "/v1/album/\(id)")
        return (response.album, response.songs)
    }

    /// 新碟上架，`area`：ALL · ZH · EA（欧美）· KR · JP
    static func newAlbums(area: String = "ALL", limit: Int = 30, offset: Int = 0) async throws -> [NeteaseAlbum] {
        struct Response: Decodable { let albums: [NeteaseAlbum] }
        return try await weapi(Response.self, "/album/new",
                               ["area": area, "limit": limit, "offset": offset, "total": true]).albums
    }

    /// 专辑是否已收藏
    static func isAlbumSubscribed(id: Int) async throws -> Bool {
        struct Response: Decodable { let isSub: Bool? }
        return try await eapi(Response.self, "/album/detail/dynamic", ["id": id]).isSub ?? false
    }

    static func subscribe(albumID: Int, _ subscribe: Bool) async throws {
        _ = try await weapi(CodeOnly.self, "/album/\(subscribe ? "sub" : "unsub")", ["id": albumID])
    }

    // MARK: - 艺人

    /// 艺人信息和热门 50 首
    static func artist(id: Int) async throws -> (artist: NeteaseArtist, hotSongs: [NeteaseTrack]) {
        struct Response: Decodable { let artist: NeteaseArtist; let hotSongs: [NeteaseTrack] }
        let response = try await weapi(Response.self, "/v1/artist/\(id)")
        return (response.artist, response.hotSongs)
    }

    static func artistAlbums(id: Int, limit: Int = 100, offset: Int = 0) async throws -> [NeteaseAlbum] {
        struct Response: Decodable { let hotAlbums: [NeteaseAlbum] }
        return try await weapi(Response.self, "/artist/albums/\(id)",
                               ["limit": limit, "offset": offset, "total": true]).hotAlbums
    }

    static func subscribe(artistID: Int, _ subscribe: Bool) async throws {
        _ = try await weapi(CodeOnly.self, "/artist/\(subscribe ? "sub" : "unsub")",
                            ["artistId": artistID, "artistIds": "[\(artistID)]"])
    }

    /// 歌手榜
    static func topArtists(limit: Int = 100) async throws -> [NeteaseArtist] {
        struct Body: Decodable { let artists: [NeteaseArtist] }
        struct Response: Decodable { let list: Body }
        return try await weapi(Response.self, "/toplist/artist",
                               ["type": 1, "limit": limit, "offset": 0, "total": true]).list.artists
    }

    static func similarArtists(id: Int) async throws -> [NeteaseArtist] {
        struct Response: Decodable { let artists: [NeteaseArtist] }
        return try await weapi(Response.self, "/discovery/simiArtist", ["artistid": id]).artists
    }

    // MARK: - 搜索

    enum SearchType: Int, Sendable {
        case songs = 1, albums = 10, artists = 100, playlists = 1000
    }

    struct SearchResult: Decodable, Sendable {
        var songs: [NeteaseTrack]?
        var albums: [NeteaseAlbum]?
        var artists: [NeteaseArtist]?
        var playlists: [NeteasePlaylist]?
        var songCount: Int?
        var albumCount: Int?
        var artistCount: Int?
        var playlistCount: Int?
    }

    static func search(_ keywords: String, type: SearchType = .songs,
                       limit: Int = 30, offset: Int = 0) async throws -> SearchResult {
        struct Response: Decodable { let result: SearchResult? }
        return try await eapi(Response.self, "/cloudsearch/pc",
                              ["s": keywords, "type": type.rawValue, "limit": limit, "offset": offset, "total": true])
            .result ?? SearchResult()
    }

    /// 输入时的搜索建议
    static func searchSuggestions(_ keywords: String) async throws -> SearchResult {
        struct Response: Decodable { let result: SearchResult? }
        return try await weapi(Response.self, "/search/suggest/web", ["s": keywords]).result ?? SearchResult()
    }

    /// 搜索框里的默认占位词
    static func defaultKeyword() async throws -> String? {
        struct Body: Decodable { let showKeyword: String? }
        struct Response: Decodable { let data: Body? }
        return try await eapi(Response.self, "/search/defaultkeyword/get").data?.showKeyword
    }

    // MARK: - 解码

    private struct CodeOnly: Decodable { let code: Int }

    private struct DataList<Item: Decodable>: Decodable { let data: [Item] }

    private static func weapi<T: Decodable>(_ type: T.Type, _ path: String,
                                            _ payload: [String: any Sendable] = [:]) async throws -> T {
        try decode(T.self, from: try await client.weapi(path, payload))
    }

    private static func eapi<T: Decodable>(_ type: T.Type, _ path: String,
                                           _ payload: [String: any Sendable] = [:]) async throws -> T {
        try decode(T.self, from: try await client.eapi(path, payload))
    }

    /// 业务错误码在响应体的 `code` 里：200 成功，301 未登录
    private static func check(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? Int, code != 200 else { return }
        if code == 301 { throw NeteaseError.needLogin }
        throw NeteaseError.api(code: code, message: (object["message"] ?? object["msg"]) as? String)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try check(data)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
