import SwiftUI

/// 全屏的“正在播放”：左边封面、歌曲信息和播放控制，右边歌词或待播清单，
/// 背景取封面的颜色做成缓慢流动的网格渐变。和 Apple Music 的全屏播放器一样。
/// 由 NowPlayingPresenter 放进窗口、负责滑进滑出。
struct NowPlayingView: View {
    let song: Song

    @Environment(Player.self) private var player
    @State private var panel: SidePanel? = .lyrics
    @State private var failure: String?

    var body: some View {
        HStack(spacing: 0) {
            songColumn
                .frame(maxWidth: .infinity)

            if let panel {
                Group {
                    switch panel {
                    case .lyrics:
                        LyricsView(style: .fullScreen)
                            // 上下边缘淡出，滚动的歌词不会被硬切
                            .mask {
                                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                                       .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                               startPoint: .top, endPoint: .bottom)
                            }
                    case .queue:
                        QueueView().frame(maxWidth: 440)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, 40)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.top, 64)
        .padding(.bottom, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ArtworkBackground(song: song, isPlaying: player.isPlaying) }
        .overlay(alignment: .bottomTrailing) { panelSwitcher.padding(16) }
        // 铺满整个窗口（包括标题栏）
        .ignoresSafeArea()
        // 背景是封面的深色调，整页按深色外观显示：文字、图标都变成白色
        .environment(\.colorScheme, .dark)
        .alert("操作失败", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: - 左边：封面和播放控制

    private var songColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkView(seed: song.artworkSeed, url: song.artworkURL, cornerRadius: 10)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                // 和 Apple Music 一样，暂停时封面缩小
                .scaleEffect(player.isPlaying ? 1 : 0.8)
                .animation(.spring(duration: 0.5, bounce: 0.25), value: player.isPlaying)
                .padding(.bottom, 32)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.system(size: 17, weight: .semibold))
                    Text("\(song.artist) — \(song.album)").font(.system(size: 15)).foregroundStyle(.secondary)
                    if let notice = player.notice {
                        Text(notice).font(.caption).foregroundStyle(.orange)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                LikeButton(song: song, circular: true) { failure = $0 }
                MoreMenu(song: song, circular: true)
            }

            NowPlayingProgress().padding(.top, 18)

            transport.padding(.top, 12)
        }
        .frame(width: 320)
    }

    private var transport: some View {
        @Bindable var player = player
        return HStack(spacing: 0) {
            TransportButton("随机播放", "shuffle", size: 17, isOn: player.isShuffled) { player.isShuffled.toggle() }
            TransportButton("上一首", "backward.fill", size: 26) { player.previous() }
            Group {
                if player.isLoading {
                    ProgressView().controlSize(.regular).frame(width: 44, height: 44)
                } else {
                    TransportButton(player.isPlaying ? "暂停" : "播放", player.isPlaying ? "pause.fill" : "play.fill",
                                    size: 36) { player.togglePlayPause() }
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(maxWidth: .infinity)
            TransportButton("下一首", "forward.fill", size: 26) { player.next() }
            TransportButton("重复", player.repeatMode == .one ? "repeat.1" : "repeat", size: 17,
                            isOn: player.repeatMode != .off) { player.cycleRepeatMode() }
        }
    }

    // MARK: - 角落的按钮

    /// 右下角切换歌词 / 待播清单；再点一次当前的就收起，左边内容居中
    private var panelSwitcher: some View {
        HStack(spacing: 2) {
            panelButton(.lyrics, title: "歌词", symbol: "quote.bubble")
            panelButton(.queue, title: "待播清单", symbol: "list.bullet")
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    private func panelButton(_ kind: SidePanel, title: String, symbol: String) -> some View {
        let isOn = panel == kind
        return Button {
            withAnimation(.spring(duration: 0.45, bounce: 0.1)) { panel = isOn ? nil : kind }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Color.primary)
                .frame(width: 34, height: 34)
                .background(isOn ? Color.white : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

extension NowPlayingView {
    /// 全屏页滑入滑出用的弹簧
    static let spring = Spring(duration: 0.5, bounce: 0.08)
}

private enum TitlebarMetrics {
    /// 标题栏按钮的高度，和 Apple Music 的一样
    static let controlHeight: CGFloat = 32
    /// 工具栏高 52pt，按钮上下各空 10pt；右边离窗口边缘也空这么多，看起来一样宽
    static let edgeInset: CGFloat = (52 - controlHeight) / 2
}

/// 全屏“正在播放”的进出场：整页和标题栏里的按钮（左边关闭，右边隔空播放和音量）一起从底部滑上来，关闭时一起滑下去。
///
/// - 不用 SwiftUI 的 transition：右边的歌词、待播清单是 ScrollView，在 macOS 上是 AppKit 的 NSScrollView，
///   它不跟着 SwiftUI 的位移动画走，会直接出现在终点。所以整页放进单独的 NSHostingView，由 AppKit 移动这个视图，
///   里面的东西一起动。
/// - 标题栏按钮有两份，见 TitlebarChrome。
struct NowPlayingPresenter: View {
    let isShown: Bool
    let onClose: () -> Void

    @Environment(Player.self) private var player
    @Environment(Account.self) private var account
    @Environment(\.openLogin) private var openLogin
    @Environment(\.navigate) private var navigate
    @Environment(\.showToast) private var showToast
    @State private var chrome = TitlebarChrome()

    var body: some View {
        let leading = hosted(closeButton)
        let trailing = hosted(OutputControls().padding(.trailing, TitlebarMetrics.edgeInset))
        NowPlayingHost(
            isShown: isShown,
            chrome: chrome,
            page: hosted(NowPlayingPage(chrome: chrome, leading: leading, trailing: trailing)),
            leading: leading,
            trailing: trailing
        )
    }

    /// 单独的 NSHostingView 拿不到这里的环境，要手动传进去
    private func hosted(_ content: some View) -> AnyView {
        AnyView(content
            .environment(player)
            .environment(account)
            .environment(\.openLogin, openLogin)
            .environment(\.navigate, navigate)
            .environment(\.showToast, showToast)
            .environment(\.colorScheme, .dark))
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 52, height: TitlebarMetrics.controlHeight)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.leading, 8)
        .help("关闭")
        .accessibilityLabel("关闭正在播放")
    }
}

/// 标题栏按钮有两份。
///
/// - 标题栏区域的点击归窗口处理（拖动窗口），整页里的按钮在那里点不到，能点的一份只能放进标题栏附件视图。
/// - 附件视图只有按钮那么大、超出的部分被裁掉，跟着整页滑的话只在最后一小段露出来。
///
/// 所以整页里再画一份，摆在附件的位置上：滑动时显示整页里的，停稳后换成附件里的。两份完全重合，切换时看不出来。
@Observable
private final class TitlebarChrome {
    var isSliding = true
    /// 附件在窗口里的位置（左上角为原点）
    var leadingFrame: CGRect?
    var trailingFrame: CGRect?
}

/// 整页的内容。滑走的途中可能已经没有当前歌曲了，这时留空
private struct NowPlayingPage: View {
    let chrome: TitlebarChrome
    let leading: AnyView
    let trailing: AnyView

    @Environment(Player.self) private var player

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let song = player.current {
                NowPlayingView(song: song)
            }
            if chrome.isSliding {
                placed(leading, at: chrome.leadingFrame)
                placed(trailing, at: chrome.trailingFrame)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func placed(_ content: AnyView, at frame: CGRect?) -> some View {
        if let frame {
            content
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
    }
}

/// 标题栏附件里的那份，滑动时藏起来
private struct TitlebarAccessory: View {
    let chrome: TitlebarChrome
    let content: AnyView

    var body: some View {
        content.opacity(chrome.isSliding ? 0 : 1)
    }
}

/// 打开时：放上整页（先停在窗口下面）、藏起工具栏里原有的按钮（侧边栏按钮、返回按钮、搜索框等）、
/// 在红绿灯同一行放上自己的按钮，再滑上来。关闭时滑下去，滑完再全部拿掉、恢复工具栏按钮
/// （提前恢复的话，它们会盖在正在滑走的整页上）。
///
/// - 只藏按钮、不收起工具栏：收起后标题栏只剩 28pt 高，按钮会贴着窗口顶边；
///   留着工具栏，附件视图的高度和工具栏一样，按钮上下有空隙，和红绿灯垂直居中。
/// - 不用 SwiftUI 的 `.toolbar(.hidden, for: .windowToolbar)`：它会连红绿灯一起藏掉。
private struct NowPlayingHost: NSViewRepresentable {
    let isShown: Bool
    let chrome: TitlebarChrome
    let page: AnyView
    let leading: AnyView
    let trailing: AnyView

    /// 铺满窗口的容器。自己不接点击，没有整页时不挡住下面的页面
    final class Container: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            let view = super.hitTest(point)
            return view === self ? nil : view
        }
    }

    final class Coordinator {
        var isShown = false
        var page: NSHostingView<AnyView>?
        var accessories: [NSTitlebarAccessoryViewController] = []
        /// 被藏起来的工具栏按钮，关闭时恢复
        var hiddenItems: [NSToolbarItem] = []
        /// 每次打开 / 关闭加一；延迟执行的操作发现已经过期就放弃，快速开关时不会错乱
        var generation = 0

        func tearDown() {
            page?.removeFromSuperview()
            page = nil
            accessories.forEach { $0.removeFromParent() }
            accessories = []
            hiddenItems.forEach { $0.isHidden = false }
            hiddenItems = []
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> Container {
        let container = Container()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: Container, context: Context) {
        let coordinator = context.coordinator
        guard isShown != coordinator.isShown, let window = container.window else { return }
        coordinator.isShown = isShown
        coordinator.generation += 1
        let generation = coordinator.generation
        if isShown && coordinator.page == nil {
            chrome.isSliding = true
            install(in: container, window: window, coordinator: coordinator)
        }
        let chrome = chrome
        // 下一轮再动：等标题栏把附件排好，量出位置，整页里的那份才摆得准；也不在视图更新中途改别的视图的状态
        DispatchQueue.main.async {
            guard coordinator.generation == generation, let page = coordinator.page,
                  coordinator.accessories.count == 2 else { return }
            window.layoutIfNeeded()
            chrome.leadingFrame = Self.frame(of: coordinator.accessories[0].view, in: container)
            chrome.trailingFrame = Self.frame(of: coordinator.accessories[1].view, in: container)
            chrome.isSliding = true
            NSAnimationContext.animate(.spring(NowPlayingView.spring)) {
                page.animator().frame.origin.y = isShown ? 0 : -container.bounds.height
            } completion: {
                guard coordinator.generation == generation else { return }
                if isShown {
                    chrome.isSliding = false
                } else {
                    coordinator.tearDown()
                }
            }
        }
    }

    private func install(in container: Container, window: NSWindow, coordinator: Coordinator) {
        // 整页：铺满容器，先放在容器下面（容器坐标原点在左下角）
        let page = NSHostingView(rootView: self.page)
        page.sizingOptions = []
        page.wantsLayer = true
        page.appearance = NSAppearance(named: .darkAqua)
        page.frame = container.bounds.offsetBy(dx: 0, dy: -container.bounds.height)
        page.autoresizingMask = [.width, .height]
        container.addSubview(page)
        page.layoutSubtreeIfNeeded()
        coordinator.page = page

        coordinator.hiddenItems = window.toolbar?.items.filter { !$0.isHidden } ?? []
        coordinator.hiddenItems.forEach { $0.isHidden = true }
        for (content, attribute) in [(leading, NSLayoutConstraint.Attribute.leading), (trailing, .trailing)] {
            let hosting = NSHostingView(rootView: TitlebarAccessory(chrome: chrome, content: content))
            hosting.appearance = NSAppearance(named: .darkAqua)
            hosting.frame.size = hosting.fittingSize
            let accessory = NSTitlebarAccessoryViewController()
            accessory.view = hosting
            accessory.layoutAttribute = attribute
            window.addTitlebarAccessoryViewController(accessory)
            coordinator.accessories.append(accessory)
        }
    }

    /// 附件在容器里的位置，换成左上角为原点，和整页的 SwiftUI 坐标一致（整页停稳时和容器重合）
    private static func frame(of view: NSView, in container: NSView) -> CGRect {
        let rect = container.convert(view.convert(view.bounds, to: nil), from: nil)
        return CGRect(x: rect.minX, y: container.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func dismantleNSView(_ container: Container, coordinator: Coordinator) {
        coordinator.generation += 1
        coordinator.tearDown()
    }
}

// MARK: - 播放控制

private struct TransportButton: View {
    let title: String
    let symbol: String
    let size: CGFloat
    var isOn: Bool?
    let action: () -> Void

    init(_ title: String, _ symbol: String, size: CGFloat, isOn: Bool? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.size = size
        self.isOn = isOn
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                // 随机 / 重复：开着是白色，关着是半透明
                .foregroundStyle(isOn == false ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 44)
                .background(isOn == true ? Color.primary.opacity(0.15) : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// 进度条和两端的时间：左边已播放，右边剩余。只有这里读取播放进度
private struct NowPlayingProgress: View {
    @Environment(Player.self) private var player
    @State private var dragValue: Double?
    @State private var isHovering = false

    var body: some View {
        let fraction = dragValue ?? player.progress
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.25))
                    Capsule().fill(Color.primary.opacity(0.85)).frame(width: max(0, geo.size.width * fraction))
                }
                .frame(height: isHovering || dragValue != nil ? 8 : 5)
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
            .frame(height: 12)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            }

            HStack {
                Text((player.duration * fraction).mmss)
                Spacer()
                Text("-" + (player.duration * (1 - fraction)).mmss)
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}

/// 右上角：隔空播放和音量
private struct OutputControls: View {
    @Environment(Player.self) private var player

    var body: some View {
        let volume = Binding { player.volume } set: {
            player.volume = $0
            player.isMuted = false
        }
        HStack(spacing: 12) {
            RoutePickerButton(player: player.output)
                .frame(width: 26, height: 26)
                .help("隔空播放")
            Divider().frame(height: 18)
            VolumeSlider(value: volume, isMuted: player.isMuted) { _ in }
                .frame(width: 110)
            Button { player.isMuted.toggle() } label: {
                SpeakerIcon(level: speakerLevel, isMuted: player.isMuted || player.volume == 0)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(player.isMuted ? "取消静音" : "静音")
            .accessibilityLabel(player.isMuted ? "取消静音" : "静音")
        }
        .padding(.horizontal, 12)
        .frame(height: TitlebarMetrics.controlHeight)
        .glassEffect(.regular, in: .capsule)
    }

    private var speakerLevel: Int {
        switch player.volume {
        case 0: 0
        case ..<0.34: 1
        case ..<0.67: 2
        default: 3
        }
    }
}

// MARK: - 背景

/// 把封面缩成 3×3 取每格的平均色，作为 3×3 网格渐变的颜色；内部控制点随时间缓慢游走。
/// 暂停时停止流动，换歌时颜色渐变过去。
private struct ArtworkBackground: View {
    let song: Song
    let isPlaying: Bool

    @State private var colors = Array(repeating: Color(white: 0.18), count: 9)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            MeshGradient(width: 3, height: 3, points: Self.points(at: context.date.timeIntervalSinceReferenceDate),
                         colors: colors)
        }
        // 压暗一点，白色文字更清楚
        .overlay(Color.black.opacity(0.18))
        .ignoresSafeArea()
        .task(id: song.id) {
            let palette = await ArtworkPalette.colors(for: song)
            withAnimation(.easeInOut(duration: 1.2)) { colors = palette }
        }
    }

    /// 四个角固定，四条边的中点沿边滑动，中心点画椭圆；每个点的速度不同，看起来不规律
    nonisolated private static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func wave(_ speed: Double, _ phase: Double) -> Float { Float(sin(time * speed + phase)) }
        return [
            [0, 0], [0.5 + 0.25 * wave(0.23, 0), 0], [1, 0],
            [0, 0.5 + 0.25 * wave(0.19, 1)],
            [0.5 + 0.22 * wave(0.29, 2), 0.5 + 0.22 * wave(0.21, 3)],
            [1, 0.5 + 0.25 * wave(0.17, 4)],
            [0, 1], [0.5 + 0.25 * wave(0.27, 5), 1], [1, 1],
        ]
    }
}

private enum ArtworkPalette {
    /// 9 种颜色，顺序从左上到右下。取不到封面时用种子生成的同色系颜色
    static func colors(for song: Song) async -> [Color] {
        if let url = song.artworkURL, let colors = await sample(url) { return colors }
        let hue = Double(song.artworkSeed % 360) / 360
        return (0..<9).map { index in
            Color(hue: (hue + Double(index % 3) * 0.04).truncatingRemainder(dividingBy: 1),
                  saturation: 0.55, brightness: 0.35 + Double(index / 3) * 0.08)
        }
    }

    /// 先把封面画进 30×30 的位图，再按 10×10 一块求平均
    private static func sample(_ url: URL) async -> [Color]? {
        guard let (data, _) = try? await URLSession.shared.data(from: url.neteaseThumbnail(points: 50)),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let side = 30
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        let cell = side / 3
        return (0..<9).map { index in
            // 位图内存从上往下存，第 0 行就是图片顶部，和网格渐变的坐标方向一致
            let row = index / 3, column = index % 3
            var sum = SIMD3<Double>(0, 0, 0)
            for y in row * cell..<(row + 1) * cell {
                for x in column * cell..<(column + 1) * cell {
                    let offset = (y * side + x) * 4
                    sum += SIMD3(Double(pixels[offset]), Double(pixels[offset + 1]), Double(pixels[offset + 2]))
                }
            }
            let average = sum / Double(cell * cell * 255)
            return adjusted(red: average.x, green: average.y, blue: average.z)
        }
    }

    /// 稍微提高饱和度、压低亮度：背景更浓郁，上面的白字也看得清
    private static func adjusted(red: Double, green: Double, blue: Double) -> Color {
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation * 1.5, 1), brightness: min(brightness, 0.8) * 0.85)
    }
}
