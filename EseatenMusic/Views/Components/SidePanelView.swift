import SwiftUI

enum SidePanel: Hashable {
    case lyrics, queue

    var title: String {
        switch self {
        case .lyrics: "歌词"
        case .queue: "待播清单"
        }
    }
}

/// 从窗口右侧滑入的歌词 / 待播清单面板，停在播放条上方。
/// 它浮在页面上面而不是占一栏，打开关闭时正文宽度不变，页面不会重新排版。
struct SidePanelView: View {
    let kind: SidePanel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(kind.title).font(.title3.bold())
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(.leading, 20)
            .padding(.trailing, 14)
            .padding(.vertical, 14)

            Divider()

            Group {
                switch kind {
                case .lyrics: LyricsView()
                case .queue: QueueView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 大面积用磨砂材质而不是 Liquid Glass：下面的封面糊开后文字才看得清，和 Apple Music 一样
        .background(.regularMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
    }
}

private func placeholder(_ text: String, style: LyricsStyle = .panel) -> some View {
    Text(text)
        .font(style.placeholderFont)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

// MARK: - 歌词

/// 歌词有两种样式：右侧面板里的，和全屏“正在播放”里更大、非当前行带模糊的
enum LyricsStyle {
    case panel
    case fullScreen

    var lineFont: Font { .system(size: self == .panel ? 20 : 32, weight: .bold) }
    var translationFont: Font { .system(size: self == .panel ? 14 : 20, weight: .semibold) }
    var placeholderFont: Font { self == .panel ? .callout : .title2.weight(.semibold) }
    /// 上下留白，让第一行和最后一行也能滚到跟随位置
    var verticalPadding: CGFloat { self == .panel ? 60 : 240 }
}

struct LyricsView: View {
    var style = LyricsStyle.panel

    @Environment(Player.self) private var player
    @State private var loaded: (songID: Song.ID, lyrics: Lyrics)?
    @State private var failed = false

    var body: some View {
        Group {
            if let song = player.current {
                if let loaded, loaded.songID == song.id {
                    content(loaded.lyrics, songID: song.id)
                } else if failed {
                    placeholder("歌词加载失败", style: style)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                placeholder("播放歌曲并在此处查看歌词。", style: style)
            }
        }
        .task(id: player.current?.id) { await load() }
    }

    @ViewBuilder
    private func content(_ lyrics: Lyrics, songID: Song.ID) -> some View {
        switch lyrics.status {
        case .instrumental:
            placeholder("纯音乐，请欣赏", style: style)
        case .unavailable:
            placeholder("暂无歌词", style: style)
        case .lines(let lines):
            if lyrics.isSynced {
                SyncedLyrics(songID: songID, lyrics: lyrics, lines: lines, style: style)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(lines) { Text($0.text).font(style == .panel ? .title3.bold() : style.lineFont) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func load() async {
        failed = false
        guard let song = player.current else { return }
        do {
            loaded = (song.id, try await Catalog.lyrics(for: song))
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

/// 只有这里读取播放进度；当前行不变时，下面的歌词列表不会重算
private struct SyncedLyrics: View {
    let songID: Song.ID
    let lyrics: Lyrics
    let lines: [Lyrics.Line]
    let style: LyricsStyle

    @Environment(Player.self) private var player

    var body: some View {
        // 稍微提前一点高亮，和人声对得更齐
        LyricsList(songID: songID, lines: lines, current: lyrics.lineIndex(at: player.elapsed + 0.3), style: style)
            .equatable()
    }
}

private struct LyricsList: View, Equatable {
    let songID: Song.ID
    let lines: [Lyrics.Line]
    let current: Int?
    let style: LyricsStyle

    @Environment(Player.self) private var player
    /// 用户手动滚动后，暂停几秒自动跟随
    @State private var followsAfter = Date.distantPast

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.songID == rhs.songID && lhs.current == rhs.current
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines) { line in
                        LyricRow(line: line, distance: current.map { abs(line.id - $0) }, style: style) {
                            guard let time = line.time else { return }
                            player.seek(toTime: time)
                            if !player.isPlaying { player.togglePlayPause() }
                        }
                        .id(line.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, style.verticalPadding)
            }
            .scrollIndicators(.never)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating { followsAfter = .now + 3 }
            }
            .onChange(of: current) { follow(proxy, animated: true) }
            .onAppear { follow(proxy, animated: false) }
        }
    }

    private func follow(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let current, Date.now >= followsAfter else { return }
        let anchor = UnitPoint(x: 0.5, y: 0.35)
        if animated {
            withAnimation(.smooth(duration: 0.5)) { proxy.scrollTo(current, anchor: anchor) }
        } else {
            proxy.scrollTo(current, anchor: anchor)
        }
    }
}

private struct LyricRow: View {
    let line: Lyrics.Line
    /// 离当前行隔了几行，当前行为 0；没有当前行时为 nil
    let distance: Int?
    let style: LyricsStyle
    let action: () -> Void

    @State private var isHovering = false

    private var isCurrent: Bool { distance == 0 }

    /// 全屏时和 Apple Music 一样，离当前行越远越模糊；鼠标移上去就看清
    private var blur: CGFloat {
        guard style == .fullScreen, !isHovering, let distance, distance > 0 else { return 0 }
        return min(CGFloat(distance), 4) * 0.8
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.text)
                    .font(style.lineFont)
                if let translation = line.translation, !translation.isEmpty {
                    Text(translation)
                        .font(style.translationFont)
                }
            }
            .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .blur(radius: blur)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.25), value: distance)
        .animation(.easeOut(duration: 0.2), value: isHovering)
    }
}

// MARK: - 待播清单

struct QueueView: View {
    @Environment(Player.self) private var player

    var body: some View {
        @Bindable var player = player
        let upcoming = player.upcoming

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ToggleCapsule("随机播放", symbol: "shuffle", isOn: player.isShuffled) {
                    player.isShuffled.toggle()
                }
                ToggleCapsule("重复", symbol: player.repeatMode == .one ? "repeat.1" : "repeat",
                              isOn: player.repeatMode != .off) {
                    player.cycleRepeatMode()
                }
            }
            .padding(12)

            HStack(alignment: .firstTextBaseline) {
                Text("继续播放").font(.title3.bold())
                Spacer()
                Button("清除") { player.clearUpcoming() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .disabled(upcoming.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 16)

            if upcoming.isEmpty {
                placeholder("没有待播的歌曲")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(upcoming) { QueueRow(song: $0) }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

/// 面板顶部的随机 / 重复开关
private struct ToggleCapsule: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    init(_ title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isOn = isOn
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct QueueRow: View {
    let song: Song

    @Environment(Player.self) private var player
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(seed: song.artworkSeed, url: song.artworkURL, cornerRadius: 4)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.callout)
                Text("\(song.artist) — \(song.album)").font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Menu {
                Button("播放") { player.jump(to: song) }
                Button("从待播清单中移除") { player.remove(song) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 8))
        .padding(.horizontal, 6)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        // 和歌曲列表一样，双击播放
        .onTapGesture(count: 2) { player.jump(to: song) }
    }
}
