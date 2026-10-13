import AVKit
import SwiftUI

/// 窗口底部悬浮的 Liquid Glass 播放条
struct PlayerBar: View {
    /// 右侧展开的歌词 / 待播清单面板
    @Binding var panel: SidePanel?
    /// 点封面打开全屏的“正在播放”
    let onExpand: () -> Void

    @Environment(Player.self) private var player
    @State private var failure: String?

    var body: some View {
        HStack(spacing: 20) {
            transport
            nowPlaying
            trailing
        }
        .padding(.horizontal, Metrics.playerBarPadding)
        .frame(height: Metrics.playerBarHeight)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 880)
        .padding(.horizontal, 24)
        .padding(.bottom, Metrics.playerBarBottomMargin)
        .alert("操作失败", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: - 左侧：播放控制

    private var transport: some View {
        HStack(spacing: 16) {
            IconButton("随机播放", "shuffle", size: 12, active: player.isShuffled) { player.isShuffled.toggle() }
            IconButton("上一首", "backward.fill", size: 16) { player.previous() }
            if player.isLoading {
                ProgressView().controlSize(.small).frame(width: 28)
            } else {
                IconButton(player.isPlaying ? "暂停" : "播放", player.isPlaying ? "pause.fill" : "play.fill", size: 24) {
                    player.togglePlayPause()
                }
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28)
            }
            IconButton("下一首", "forward.fill", size: 16) { player.next() }
            IconButton("重复", player.repeatMode == .one ? "repeat.1" : "repeat", size: 12,
                       active: player.repeatMode != .off) { player.cycleRepeatMode() }
        }
        // 和 Apple Music 一样，没有歌曲时整组置灰
        .disabled(player.current == nil)
    }

    // MARK: - 中间：正在播放

    @ViewBuilder
    private var nowPlaying: some View {
        HStack(spacing: 12) {
            if let song = player.current {
                ExpandableArtwork(song: song, action: onExpand)

                VStack(alignment: .leading, spacing: 2) {
                    // 和 Apple Music 一样：歌名后面是红心，右边是“…”菜单
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(song.title).font(.callout.weight(.semibold)).lineLimit(1)
                                LikeButton(song: song) { failure = $0 }
                            }

                            Group {
                                if let notice = player.notice {
                                    Text(notice).foregroundStyle(.orange)
                                } else {
                                    Text("\(song.artist) — \(song.album)").foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        MoreMenu(song: song)
                    }

                    ProgressScrubber()
                }
            } else {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 右侧：歌词、待播清单、音量

    private var trailing: some View {
        TrailingControls(panel: $panel)
    }
}

private struct IconButton: View {
    let title: String
    let symbol: String
    let size: CGFloat
    var active = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, _ symbol: String, size: CGFloat, active: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.size = size
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(style)
                .frame(minWidth: 20, minHeight: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private var style: AnyShapeStyle {
        if !isEnabled { AnyShapeStyle(.tertiary) } else if active { AnyShapeStyle(.tint) } else { AnyShapeStyle(.primary) }
    }
}

// MARK: - 右侧按钮

/// 右侧四个按钮。点喇叭后展开成一条 Liquid Glass 胶囊，宽度正好盖住这四个按钮，
/// 不会挡到中间的进度条和时间。鼠标移开胶囊就收起，胶囊里的喇叭用来切换静音。
private struct TrailingControls: View {
    @Binding var panel: SidePanel?

    @Environment(Player.self) private var player
    @State private var isExpanded = false
    @State private var isHovering = false
    @State private var isDragging = false
    @State private var collapseTask: Task<Void, Never>?

    private static let spacing: CGFloat = 4
    private static let pillHeight: CGFloat = 44
    /// 胶囊比按钮组左边多出来的宽度
    private static let leadingInset: CGFloat = 5
    /// 右端要和播放条的圆角同心：离播放条右边缘的距离等于两者半径之差（也就是上下的间距）
    private static var trailingInset: CGFloat {
        Metrics.playerBarPadding - (Metrics.playerBarHeight - pillHeight) / 2
    }
    private static var clusterWidth: CGFloat { BarMetrics.buttonSize * 4 + spacing * 3 }
    private static var sliderWidth: CGFloat {
        clusterWidth + leadingInset - 14 - 6 - BarMetrics.buttonSize
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: Self.spacing) {
                BarButton("歌词", "quote.bubble", active: panel == .lyrics) { toggle(.lyrics) }
                BarButton("待播清单", "list.bullet", active: panel == .queue) { toggle(.queue) }
                RoutePickerButton(player: player.output)
                    .frame(width: BarMetrics.buttonSize, height: BarMetrics.buttonSize)
                    .help("隔空播放")
                BarButton("音量", action: expand) { speakerIcon }
            }
            .opacity(isExpanded ? 0 : 1)
            .allowsHitTesting(!isExpanded)

            pill
        }
        .frame(height: Self.pillHeight)
        .contentShape(.rect)
        .onHover { hovering in
            isHovering = hovering
            scheduleCollapse()
        }
    }

    private var speakerIcon: SpeakerIcon {
        let level = switch player.volume {
        case 0: 0
        case ..<0.34: 1
        case ..<0.67: 2
        default: 3
        }
        return SpeakerIcon(level: level, isMuted: player.isMuted || player.volume == 0)
    }

    /// 从喇叭处向左长出来的胶囊；滑块固定在最终位置，随胶囊变宽逐渐露出来
    private var pill: some View {
        let volume = Binding {
            player.volume
        } set: {
            player.volume = $0
            player.isMuted = false
        }
        return HStack(spacing: 6) {
            VolumeSlider(value: volume, isMuted: player.isMuted) { dragging in
                isDragging = dragging
                scheduleCollapse()
            }
            .frame(width: Self.sliderWidth)
            BarButton(player.isMuted ? "取消静音" : "静音", action: { player.isMuted.toggle() }) { speakerIcon }
        }
        .padding(.trailing, Self.trailingInset)
        .frame(width: (isExpanded ? Self.clusterWidth + Self.leadingInset : BarMetrics.buttonSize) + Self.trailingInset,
               height: Self.pillHeight, alignment: .trailing)
        .clipShape(.capsule)
        .glassEffect(.regular.interactive(), in: .capsule)
        .opacity(isExpanded ? 1 : 0)
        .padding(.leading, isExpanded ? -Self.leadingInset : 0)
        .padding(.trailing, -Self.trailingInset)
        .allowsHitTesting(isExpanded)
    }

    private func toggle(_ kind: SidePanel) {
        withAnimation(.spring(duration: 0.4, bounce: 0.1)) {
            panel = panel == kind ? nil : kind
        }
    }

    private func expand() {
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { isExpanded = true }
        scheduleCollapse(after: .seconds(2))
    }

    /// 鼠标不在胶囊上、也没在拖滑块时收起。
    /// 刚展开时多等一会儿，免得用键盘展开后鼠标还没移过来就收起了。
    private func scheduleCollapse(after delay: Duration = .milliseconds(350)) {
        collapseTask?.cancel()
        guard isExpanded, !isHovering, !isDragging else { return }
        collapseTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.4, bounce: 0.1)) { isExpanded = false }
        }
    }
}

private enum BarMetrics {
    static let buttonSize: CGFloat = 34
    static let iconFont = Font.system(size: 18, weight: .medium)
}

/// 播放条右侧的图标按钮：按下时图标缩小、出现圆形底，松开恢复
private struct BarButton<Icon: View>: View {
    let title: String
    var active = false
    let action: () -> Void
    @ViewBuilder var icon: Icon

    init(_ title: String, active: Bool = false, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.active = active
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        Button(action: action) {
            icon
                .font(BarMetrics.iconFont)
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: BarMetrics.buttonSize, height: BarMetrics.buttonSize)
                .contentShape(.circle)
        }
        .buttonStyle(PressableIconStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

extension BarButton where Icon == Image {
    init(_ title: String, _ symbol: String, active: Bool = false, action: @escaping () -> Void) {
        self.init(title, active: active, action: action) { Image(systemName: symbol) }
    }
}

/// 隔空播放：直接用系统的选择器，弹出的设备列表由系统绘制。选中设备后切换的是这个播放器的输出，
/// 输出到其他设备时图标变成强调色。
struct RoutePickerButton: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        let accent = NSColor(named: "AccentColor") ?? .controlAccentColor
        view.setRoutePickerButtonColor(.labelColor, for: .normal)
        view.setRoutePickerButtonColor(.secondaryLabelColor, for: .normalHighlighted)
        view.setRoutePickerButtonColor(accent, for: .active)
        view.setRoutePickerButtonColor(accent.withAlphaComponent(0.7), for: .activeHighlighted)
        view.player = player
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player
        // NSView 不跟 SwiftUI 的 colorScheme 走，全屏“正在播放”里要手动切成深色外观，图标才是白的
        view.appearance = context.environment.colorScheme == .dark ? NSAppearance(named: .darkAqua) : nil
    }
}

/// 音量图标。和 Apple Music 一样，音量变化时只增减喇叭右边的声波：
/// 把 1、2、3 格声波的图标叠在一起，喇叭部分完全重合，只淡入淡出最外面那一格。
/// 静音（或音量为 0）时喇叭换成带斜杠的，斜杠用系统的 Magic Replace 画出来。
struct SpeakerIcon: View {
    let level: Int
    let isMuted: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
            ForEach(1...3, id: \.self) { wave in
                Image(systemName: "speaker.wave.\(wave).fill")
                    .opacity(!isMuted && level >= wave ? 1 : 0)
            }
        }
        .animation(.easeOut(duration: 0.18), value: level)
        .animation(.easeOut(duration: 0.25), value: isMuted)
    }
}

private struct PressableIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableIcon(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct PressableIcon<Label: View>: View {
    let label: Label
    let isPressed: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        label
            .scaleEffect(isPressed ? 0.82 : 1)
            .background {
                Circle()
                    .fill(.white.opacity(colorScheme == .dark ? 0.18 : 0.6))
                    .scaleEffect(isPressed ? 1 : 0.5)
                    .opacity(isPressed ? 1 : 0)
            }
            .animation(.spring(duration: 0.25, bounce: 0.3), value: isPressed)
    }
}

/// Apple Music 那种粗条音量滑块，静音时只剩底槽
struct VolumeSlider: View {
    @Binding var value: Double
    var isMuted: Bool
    var onDragging: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 玻璃里的 .primary 会被处理成半透明的灰，这里要实心的黑 / 白
        let ink: Color = colorScheme == .dark ? .white : .black
        GeometryReader { geo in
            Capsule()
                .fill(ink.opacity(0.15))
                .overlay(alignment: .leading) {
                    Rectangle().fill(ink).frame(width: geo.size.width * value)
                        .opacity(isMuted ? 0 : 1)
                }
                .clipShape(.capsule)
                .frame(height: 8)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .animation(.easeOut(duration: 0.2), value: isMuted)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged {
                            value = min(max($0.location.x / geo.size.width, 0), 1)
                            onDragging(true)
                        }
                        .onEnded { _ in onDragging(false) }
                )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("音量")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 0.1, 1)
            case .decrement: value = max(value - 0.1, 0)
            @unknown default: break
            }
        }
    }
}

// MARK: - 正在播放的歌曲操作

/// 歌名后面的红心，点了喜爱 / 取消喜爱
struct LikeButton: View {
    let song: Song
    /// 全屏“正在播放”里用圆底的大按钮
    var circular = false
    let onFailure: (String) -> Void

    @Environment(Account.self) private var account
    @Environment(\.openLogin) private var openLogin

    var body: some View {
        let isLiked = account.likedSongIDs.contains(song.id)
        Button(action: toggle) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: circular ? 14 : 12, weight: .semibold))
                .foregroundStyle(isLiked ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .contentTransition(.symbolEffect(.replace))
                .circularBackground(circular)
                .frame(height: circular ? nil : 18)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isLiked ? "取消喜爱" : "喜爱")
        .accessibilityLabel(isLiked ? "取消喜爱" : "喜爱")
    }

    private func toggle() {
        guard account.isLoggedIn else {
            openLogin()
            return
        }
        Task {
            do {
                try await account.toggleLike(song)
            } catch {
                onFailure("“\(song.title)”\(account.likedSongIDs.contains(song.id) ? "取消喜爱" : "喜爱")失败：\(error.localizedDescription)")
            }
        }
    }
}

/// “…”菜单：喜爱、添加到歌单、前往歌手
struct MoreMenu: View {
    let song: Song
    /// 全屏“正在播放”里用圆底的大按钮
    var circular = false

    var body: some View {
        Menu {
            SongMenuItems(song: song)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: circular ? 14 : 16, weight: .bold))
                .frame(width: 28, height: 28)
                .circularBackground(circular)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("更多")
        .accessibilityLabel("更多")
    }
}

private extension View {
    /// 全屏“正在播放”里红心和“…”的半透明圆底
    @ViewBuilder
    func circularBackground(_ isOn: Bool) -> some View {
        if isOn {
            frame(width: 32, height: 32).background(Color.primary.opacity(0.15), in: .circle)
        } else {
            self
        }
    }
}

/// 播放条上的封面：悬停时放大、浮起阴影并露出展开图标，点击打开全屏的“正在播放”
private struct ExpandableArtwork: View {
    let song: Song
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ArtworkView(seed: song.artworkSeed, url: song.artworkURL, cornerRadius: 5)
                .frame(width: 40, height: 40)
                .overlay {
                    if isHovering {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.black.opacity(0.35))
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .scaleEffect(isHovering ? 1.12 : 1)
                .shadow(color: .black.opacity(isHovering ? 0.3 : 0), radius: 6, y: 3)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(duration: 0.25, bounce: 0.3)) { isHovering = hovering }
        }
        .help("打开正在播放")
        .accessibilityLabel("打开正在播放")
    }
}

// 播放进度每 0.25 秒变一次。只让进度条读取 `elapsed`，进度变化时就只重算它，而不是整个播放条。

/// 细进度条，悬停变粗，可拖动
private struct ProgressScrubber: View {
    @Environment(Player.self) private var player
    @State private var isHovering = false
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geo in
            let fraction = dragValue ?? player.progress
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule()
                    .fill(Color.primary.opacity(isHovering ? 0.75 : 0.5))
                    .frame(width: max(0, geo.size.width * fraction))
            }
            .frame(height: isHovering ? 6 : 3)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragValue = min(max($0.location.x / geo.size.width, 0), 1) }
                    .onEnded { _ in
                        if let dragValue { player.seek(to: dragValue) }
                        dragValue = nil
                    }
            )
        }
        .frame(height: 10)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}
