import SwiftUI

/// 全屏的“正在播放”：左边封面、歌曲信息和播放控制，右边歌词或待播清单，
/// 背景取封面的颜色做成缓慢流动的网格渐变。和 Apple Music 的全屏播放器一样。
struct NowPlayingView: View {
    let song: Song
    let onClose: () -> Void

    @Environment(Player.self) private var player
    @Environment(Account.self) private var account
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
        // 关闭按钮和隔空播放、音量放进标题栏，和红绿灯同一行
        .background {
            TitlebarAccessories(
                leading: closeButton,
                trailing: OutputControls().padding(.trailing, TitlebarMetrics.edgeInset),
                player: player, account: account
            )
        }
        // Esc 关闭；标题栏里的按钮收不到窗口内容的快捷键，单独放一个
        .background {
            Button("关闭", action: onClose).keyboardShortcut(.cancelAction).hidden()
        }
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

private enum TitlebarMetrics {
    /// 标题栏按钮的高度，和 Apple Music 的一样
    static let controlHeight: CGFloat = 32
    /// 工具栏高 52pt，按钮上下各空 10pt；右边离窗口边缘也空这么多，看起来一样宽
    static let edgeInset: CGFloat = (52 - controlHeight) / 2
}

/// 显示时藏起工具栏里原有的按钮（侧边栏按钮、返回按钮、搜索框等），在红绿灯同一行放上自己的按钮，关闭后恢复。
///
/// - 标题栏区域的点击归窗口处理（拖动窗口），放在内容里的按钮点不到，所以用标题栏附件视图。
/// - 只藏按钮、不收起工具栏：收起后标题栏只剩 28pt 高，按钮会贴着窗口顶边；
///   留着工具栏，附件视图的高度和工具栏一样，按钮上下有空隙，和红绿灯垂直居中。
/// - 不用 SwiftUI 的 `.toolbar(.hidden, for: .windowToolbar)`：它会连红绿灯一起藏掉。
private struct TitlebarAccessories<Leading: View, Trailing: View>: NSViewRepresentable {
    let leading: Leading
    let trailing: Trailing
    /// 附件视图在单独的 NSHostingView 里，拿不到这里的环境，要手动传进去
    let player: Player
    let account: Account

    final class Coordinator {
        var accessories: [NSTitlebarAccessoryViewController] = []
        /// 被藏起来的工具栏按钮，关闭时恢复
        var hiddenItems: [NSToolbarItem] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        let views = [(AnyView(leading), NSLayoutConstraint.Attribute.leading),
                     (AnyView(trailing), NSLayoutConstraint.Attribute.trailing)]
        let player = player, account = account
        // 刚创建时还没放进窗口，等下一轮
        DispatchQueue.main.async {
            guard coordinator.accessories.isEmpty, let window = view.window else { return }
            coordinator.hiddenItems = window.toolbar?.items.filter { !$0.isHidden } ?? []
            coordinator.hiddenItems.forEach { $0.isHidden = true }
            for (content, attribute) in views {
                let hosting = NSHostingView(rootView: content
                    .environment(player)
                    .environment(account)
                    .environment(\.colorScheme, .dark))
                hosting.appearance = NSAppearance(named: .darkAqua)
                hosting.frame.size = hosting.fittingSize
                let accessory = NSTitlebarAccessoryViewController()
                accessory.view = hosting
                accessory.layoutAttribute = attribute
                window.addTitlebarAccessoryViewController(accessory)
                coordinator.accessories.append(accessory)
            }
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.accessories.forEach { $0.removeFromParent() }
        coordinator.accessories = []
        coordinator.hiddenItems.forEach { $0.isHidden = false }
        coordinator.hiddenItems = []
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
