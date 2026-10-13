import AVFoundation
import Foundation
import Observation

/// 播放器：从网易云取播放地址，用 AVPlayer 播放
@Observable
@MainActor
final class Player {
    enum RepeatMode { case off, all, one }

    private(set) var current: Song?
    private(set) var queue: [Song] = []
    private(set) var isPlaying = false
    /// 正在取播放地址 / 缓冲
    private(set) var isLoading = false
    /// 给用户看的提示，比如“只能试听”“无法播放”
    private(set) var notice: String?
    var elapsed: TimeInterval = 0
    /// 实际能播放的长度：试听时是片段长度，否则是整首歌
    private(set) var duration: TimeInterval = 0
    /// 音量存在本地，下次启动沿用
    var volume: Double = UserDefaults.standard.object(forKey: Player.volumeKey) as? Double ?? 0.7 {
        didSet {
            engine.volume = Float(volume)
            UserDefaults.standard.set(volume, forKey: Self.volumeKey)
        }
    }
    /// 静音单独存，取消静音后回到原来的音量
    var isMuted: Bool = UserDefaults.standard.bool(forKey: Player.mutedKey) {
        didSet {
            engine.isMuted = isMuted
            UserDefaults.standard.set(isMuted, forKey: Self.mutedKey)
        }
    }
    /// 随机播放时直接打乱 `queue`（当前歌曲排第一），这样待播清单显示的就是真实顺序
    var isShuffled = false {
        didSet { if isShuffled != oldValue { reorder() } }
    }
    var repeatMode: RepeatMode = .off

    @ObservationIgnored private let engine = AVPlayer()
    @ObservationIgnored private var observers: [Any] = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// 连续播放失败的次数，用来在整张歌单都放不了时停下来
    @ObservationIgnored private var failureStreak = 0
    /// 队列播完时用来续上更多歌曲（私人漫游）
    @ObservationIgnored private var refill: (@MainActor () async throws -> [Song])?
    /// 打乱之前的顺序，关掉随机播放时恢复
    @ObservationIgnored private var originalQueue: [Song] = []
    private static let volumeKey = "player.volume"
    private static let mutedKey = "player.muted"

    init() {
        engine.volume = Float(volume)
        engine.isMuted = isMuted
        observers.append(engine.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.timeDidChange(time) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidFinish() }
        })
    }

    /// 隔空播放选择器绑定到这个 AVPlayer，切换的是它的输出设备
    var output: AVPlayer { engine }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(elapsed / duration, 1)
    }

    /// 当前歌曲之后还要播的歌
    var upcoming: ArraySlice<Song> {
        guard let current, let index = queue.firstIndex(of: current) else { return queue[...] }
        return queue[(index + 1)...]
    }

    func play(_ song: Song, in queue: [Song]? = nil) {
        if let queue {
            originalQueue = queue
            self.queue = isShuffled ? Self.shuffled(queue, first: song) : queue
        }
        refill = nil
        failureStreak = 0
        start(song)
    }

    func play(_ songs: [Song]) {
        guard let first = isShuffled ? songs.randomElement() : songs.first else { return }
        play(first, in: songs)
    }

    /// 先加载专辑 / 歌单里的歌曲再播放（卡片上的播放按钮用）
    func play(_ destination: Destination) {
        Task {
            do {
                play(try await Catalog.songs(in: destination))
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    /// 无尽队列：每次播完都调用 `load` 续上几首，私人漫游用
    func playRadio(_ load: @escaping @MainActor () async throws -> [Song]) {
        Task {
            do {
                let songs = try await load()
                play(songs)
                refill = load
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    func togglePlayPause() {
        guard let current else { return }
        if isPlaying {
            engine.pause()
            isPlaying = false
        } else if engine.currentItem == nil {
            start(current)
        } else {
            engine.play()
            isPlaying = true
        }
    }

    func next() { advance(by: 1) }

    /// 播放超过 3 秒时先回到开头，和 Apple Music 一致
    func previous() {
        if elapsed > 3 { seek(to: 0) } else { advance(by: -1) }
    }

    func seek(to fraction: Double) {
        seek(toTime: duration * fraction)
    }

    func seek(toTime time: TimeInterval) {
        guard current != nil else { return }
        elapsed = min(max(time, 0), duration)
        engine.seek(to: CMTime(seconds: elapsed, preferredTimescale: 600))
    }

    /// 播放待播清单里的某一首，不改变清单
    func jump(to song: Song) {
        guard queue.contains(song) else { return }
        failureStreak = 0
        start(song)
    }

    func remove(_ song: Song) {
        guard song != current else { return }
        queue.removeAll { $0 == song }
        originalQueue.removeAll { $0 == song }
    }

    /// 清空当前歌曲之后的待播歌曲
    func clearUpcoming() {
        guard let current, let index = queue.firstIndex(of: current) else { return }
        let removed = Set(queue[(index + 1)...].map(\.id))
        queue.removeSubrange((index + 1)...)
        originalQueue.removeAll { removed.contains($0.id) }
        refill = nil
    }

    func cycleRepeatMode() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    // MARK: - 内部

    private static func shuffled(_ songs: [Song], first: Song?) -> [Song] {
        guard let first else { return songs.shuffled() }
        return [first] + songs.filter { $0 != first }.shuffled()
    }

    private func reorder() {
        if isShuffled {
            originalQueue = queue
            queue = Self.shuffled(queue, first: current)
        } else {
            // 恢复原顺序，期间被移除的歌不再加回来
            let remaining = Set(queue.map(\.id))
            queue = originalQueue.filter { remaining.contains($0.id) }
        }
    }

    private func start(_ song: Song) {
        current = song
        elapsed = 0
        duration = song.duration
        notice = nil
        isPlaying = true
        isLoading = true
        engine.replaceCurrentItem(with: nil)
        loadTask?.cancel()
        loadTask = Task {
            do {
                let stream = try await Catalog.stream(for: song)
                guard !Task.isCancelled else { return }
                failureStreak = 0
                if let trial = stream.trialLength {
                    duration = trial
                    notice = "未登录或非 VIP，只能试听 \(Int(trial)) 秒"
                }
                engine.replaceCurrentItem(with: AVPlayerItem(url: stream.url))
                if isPlaying { engine.play() }
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                failureStreak += 1
                notice = "“\(song.title)”无法播放：\(error.localizedDescription)"
                // 跳过放不了的歌；整个队列都放不了就停下
                if failureStreak < queue.count {
                    advance(by: 1, keepsNotice: true)
                } else {
                    isPlaying = false
                }
            }
        }
    }

    private func advance(by step: Int, keepsNotice: Bool = false) {
        guard let current, !queue.isEmpty else { return }
        let index = queue.firstIndex(of: current) ?? 0
        if let refill, step > 0, index == queue.count - 1 {
            // 私人漫游播到最后一首：续上新的再接着放
            Task {
                guard let more = try? await refill(), !more.isEmpty else { return }
                queue += more
                originalQueue += more
                start(more[0])
            }
            return
        }
        let target = (index + step + queue.count) % queue.count
        let notice = notice
        start(queue[target])
        if keepsNotice { self.notice = notice }
    }

    private func timeDidChange(_ time: CMTime) {
        guard engine.currentItem != nil, time.isNumeric else { return }
        elapsed = time.seconds
    }

    private func itemDidFinish() {
        guard let current else { return }
        if repeatMode == .one {
            seek(to: 0)
            engine.play()
        } else if repeatMode == .off, refill == nil, queue.last == current {
            // 不循环时播完最后一首就停
            isPlaying = false
            engine.replaceCurrentItem(with: nil)
            elapsed = 0
        } else {
            next()
        }
    }
}
