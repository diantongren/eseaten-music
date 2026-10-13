import Foundation

enum NeteaseError: LocalizedError {
    case http(Int)
    case api(code: Int, message: String?)
    case needLogin
    /// 拿不到播放地址：无版权、VIP 专属等
    case unavailable

    var errorDescription: String? {
        switch self {
        case .http(let status): "网络错误（\(status)）"
        case .api(let code, let message): message ?? "接口错误（\(code)）"
        case .needLogin: "需要登录网易云音乐"
        case .unavailable: "暂无版权或需要 VIP"
        }
    }
}

/// 网易云的传输层：负责加密、发请求、管理登录 Cookie
///
/// Cookie 自己维护（URLSession 的 Cookie 存储关掉），登录态只看 `MUSIC_U` 和 `__csrf`，
/// 持久化到 Application Support 下的一个 JSON 文件。
///
/// weapi 按网页端的身份发，eapi 按 PC 客户端的身份发（Cookie 多带 `os=pc`、`appver`）。
/// 两种身份不能混：weapi 带上 `os=pc` 会被当成客户端，收藏歌单等接口直接返回 405“操作过于频繁”。
actor NeteaseClient {
    static let shared = NeteaseClient()

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    /// 模拟 PC 客户端的版本号，eapi 的 header 和 Cookie 都要带
    private static let appVersion = "3.1.17"

    private let session: URLSession
    private let cookieFile: URL
    private var cookies: [String: String]

    init() {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)

        let folder = URL.applicationSupportDirectory.appending(path: "com.eseaten.music", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cookieFile = folder.appending(path: "netease-cookies.json")
        cookies = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: cookieFile))) ?? [:]
    }

    // MARK: - 登录态

    var isLoggedIn: Bool { cookies["MUSIC_U"] != nil }

    func clearLogin() {
        cookies["MUSIC_U"] = nil
        cookies["__csrf"] = nil
        saveCookies()
    }

    /// 二维码登录成功时，响应体里的 `cookie` 字段是用 `;;` 拼起来的一串 Set-Cookie
    func absorbCookieString(_ raw: String) {
        for item in raw.components(separatedBy: ";;") {
            guard let pair = item.split(separator: ";").first,
                  let eq = pair.firstIndex(of: "=") else { continue }
            let name = pair[..<eq].trimmingCharacters(in: .whitespaces)
            let value = pair[pair.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !value.isEmpty { cookies[name] = value }
        }
        saveCookies()
    }

    // MARK: - 请求

    /// POST `https://music.163.com/weapi{path}`
    func weapi(_ path: String, _ payload: [String: any Sendable] = [:]) async throws -> Data {
        let csrf = cookies["__csrf"] ?? ""
        var body = payload
        body["csrf_token"] = csrf
        let form = NeteaseCrypto.weapi(try JSONSerialization.data(withJSONObject: body as [String: Any]))

        var url = "https://music.163.com/weapi\(path)"
        if !csrf.isEmpty { url += (path.contains("?") ? "&" : "?") + "csrf_token=\(csrf)" }
        return try await post(url, form: form, sending: cookies)
    }

    /// POST `https://interface.music.163.com/eapi{path}`，摘要按对应的 `/api{path}` 计算
    func eapi(_ path: String, _ payload: [String: any Sendable] = [:], cookieOverrides: [String: String] = [:]) async throws -> Data {
        var header: [String: String] = [
            "os": "pc",
            "appver": Self.appVersion,
            "osver": "Mac OS X 15",
            "deviceId": "eseaten-music",
            "requestId": String(Int.random(in: 20_000_000...30_000_000)),
            "versioncode": "140",
            "buildver": String(Int(Date.now.timeIntervalSince1970)),
            "resolution": "1920x1080",
            "channel": "",
            "clientSign": "",
        ]
        header["MUSIC_U"] = cookies["MUSIC_U"]
        header["__csrf"] = cookies["__csrf"]

        var body = payload
        body["header"] = header
        let json = try JSONSerialization.data(withJSONObject: body as [String: Any])
        let form = NeteaseCrypto.eapi(apiPath: "/api\(path)", json: json)
        var clientCookies = cookies
        clientCookies["os"] = clientCookies["os"] ?? "pc"
        clientCookies["appver"] = clientCookies["appver"] ?? Self.appVersion
        clientCookies.merge(cookieOverrides) { _, new in new }
        return try await post("https://interface.music.163.com/eapi\(path)", form: form, sending: clientCookies)
    }

    private func post(_ address: String, form: [String: String], sending requestCookies: [String: String]) async throws -> Data {
        let url = URL(string: address)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(requestCookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.httpBody = Data(form.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NeteaseError.http(-1) }
        absorbSetCookie(from: http, url: url)
        guard (200..<300).contains(http.statusCode) else { throw NeteaseError.http(http.statusCode) }
        return data
    }

    // MARK: - Cookie

    private func absorbSetCookie(from response: HTTPURLResponse, url: URL) {
        guard let fields = response.allHeaderFields as? [String: String] else { return }
        let received = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            .filter { !$0.value.isEmpty && $0.value != "\"\"" }
        guard !received.isEmpty else { return }
        for cookie in received { cookies[cookie.name] = cookie.value }
        saveCookies()
    }

    private func saveCookies() {
        if let data = try? JSONEncoder().encode(cookies) {
            try? data.write(to: cookieFile, options: .atomic)
        }
    }

    /// 表单值里除了 `A-Z a-z 0-9 - . _ ~` 全部百分号编码（base64 里的 `+` `/` `=` 必须编码）
    private static let formAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? value
    }
}
