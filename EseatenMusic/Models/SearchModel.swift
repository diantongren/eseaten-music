import Foundation
import Observation

/// 搜索页的状态。放在 ContentView 里，切换侧边栏再回来时关键词和结果都还在；
/// 关键词和范围还会存进 UserDefaults，下次启动打开搜索页时接着显示。
@Observable
@MainActor
final class SearchModel {
    enum Scope: String, CaseIterable, Identifiable, Sendable {
        case songs = "单曲"
        case albums = "专辑"
        case artists = "歌手"
        case playlists = "歌单"

        var id: Self { self }
    }

    enum Results: Sendable {
        case songs([Song])
        case albums([Album])
        case artists([Artist])
        case playlists([Playlist])
    }

    struct Key: Hashable, Sendable {
        let keyword: String
        let scope: Scope
    }

    var text: String {
        didSet { UserDefaults.standard.set(text, forKey: Self.textKey) }
    }
    var scope: Scope {
        didSet { UserDefaults.standard.set(scope.rawValue, forKey: Self.scopeKey) }
    }
    /// 正在显示的结果；输入新关键词时先保留旧结果，新结果到了再替换，避免闪烁
    private(set) var shown: (key: Key, results: Results)?
    private(set) var isLoading = false
    private(set) var error: (any Error)?

    @ObservationIgnored private var cache: [Key: Results] = [:]
    /// 缓存的先后顺序，超过上限时丢掉最早的
    @ObservationIgnored private var cacheOrder: [Key] = []
    private static let cacheLimit = 30
    private static let textKey = "search.text"
    private static let scopeKey = "search.scope"

    init() {
        text = UserDefaults.standard.string(forKey: Self.textKey) ?? ""
        scope = UserDefaults.standard.string(forKey: Self.scopeKey).flatMap(Scope.init) ?? .songs
    }

    var key: Key {
        Key(keyword: text.trimmingCharacters(in: .whitespacesAndNewlines), scope: scope)
    }

    /// 加载当前关键词的结果：有缓存直接用，否则停顿一下再请求（继续输入会取消上一次）
    func load() async {
        let key = key
        error = nil
        guard !key.keyword.isEmpty else {
            isLoading = false
            return
        }
        if let cached = cache[key] {
            shown = (key, cached)
            isLoading = false
            return
        }
        isLoading = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            let results = try await Catalog.search(key.keyword, scope: key.scope)
            store(results, for: key)
            shown = (key, results)
            isLoading = false
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error
            isLoading = false
        }
    }

    private func store(_ results: Results, for key: Key) {
        if cache.updateValue(results, forKey: key) == nil { cacheOrder.append(key) }
        while cacheOrder.count > Self.cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }
}
