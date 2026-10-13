import SwiftUI

/// 专辑 / 播放列表详情页。网易云的专辑和歌单进来时只有概要，歌曲和简介在这里加载
struct CollectionDetailView<C: TrackCollection>: View {
    let collection: C

    @Environment(Player.self) private var player
    @Environment(Account.self) private var account
    @Environment(\.openLogin) private var openLogin
    @Environment(\.showToast) private var showToast
    @State private var detail: Catalog.CollectionDetail?
    @State private var error: (any Error)?
    /// 同一艺人的其他专辑
    @State private var moreAlbums: [Album] = []
    /// 专辑是否已收藏；歌单的收藏状态直接看账号里的收藏歌单
    @State private var isAlbumCollected = false
    /// “我喜欢的音乐”里刚取消喜爱的歌，先从列表里拿掉；重新喜爱（或接口失败改回来）就放回原位
    @State private var unlikedIDs: Set<Song.ID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if let detail {
                        TrackList(songs: songs, showsArtist: showsArtist(in: detail.songs), showsArtwork: isPlaylist,
                                  playlist: ownPlaylist) { song in
                            withAnimation { self.detail?.songs.removeAll { $0.id == song.id } }
                        }
                        if !songs.isEmpty { footer(detail) }
                    } else if let error {
                        ContentUnavailableView("加载失败", systemImage: "wifi.exclamationmark",
                                               description: Text(error.localizedDescription))
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, Metrics.margin)

                // 货架自带左右边距，放在上面的 VStack 外面
                if let artist = detail?.artist, !moreAlbums.isEmpty {
                    Shelf(title: "更多\(artist.name)的作品", items: moreAlbums, destination: .artist(artist)) { album in
                        CollectionCard(collection: album, subtitle: album.year > 0 ? "\(album.year) 年" : nil)
                    }
                }
            }
            .padding(.vertical, 28)
        }
        .navigationTitle(collection.title)
        .onChange(of: account.likedSongIDs) { old, new in
            guard isLikedPlaylist else { return }
            withAnimation {
                unlikedIDs.formUnion(old.subtracting(new))
                unlikedIDs.subtract(new)
            }
        }
        .task(id: collection.id) {
            moreAlbums = []
            unlikedIDs = []
            do {
                let detail = try await Catalog.detail(of: collection.destination)
                self.detail = detail
                if case .album(let album) = collection.destination, account.isLoggedIn {
                    isAlbumCollected = (try? await account.isCollected(album)) ?? false
                }
                if let artist = detail.artist, let albums = try? await Catalog.albums(by: artist) {
                    moreAlbums = albums.filter { $0.id != collection.id }
                }
            } catch {
                if !Task.isCancelled { self.error = error }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ArtworkView(seed: collection.artworkSeed, url: collection.artworkURL,
                        cornerRadius: 10, label: collection.artworkLabel)
                .frame(width: 240, height: 240)
                .shadow(color: .black.opacity(0.2), radius: 14, y: 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(collection.title).font(.system(size: 30, weight: .bold)).lineLimit(2)
                Text(collection.subtitle).font(.title2).foregroundStyle(.tint).lineLimit(1)
                if !caption.isEmpty {
                    Text(caption).font(.subheadline).foregroundStyle(.secondary)
                }

                if let description = detail?.description, !description.isEmpty {
                    CollectionDescription(title: collection.title, text: description)
                        .padding(.top, 10)
                }

                actions.padding(.top, 14)
            }
        }
    }

    /// 和 Apple Music 一样：圆形随机播放、胶囊播放、圆形“+”（收藏）
    private var actions: some View {
        HStack(spacing: 10) {
            Group {
                Button { player.play(songs.shuffled()) } label: {
                    Image(systemName: "shuffle").frame(width: HeaderButtonStyle.height)
                }
                .help("随机播放")
                .accessibilityLabel("随机播放")

                Button { player.play(songs) } label: {
                    Label("播放", systemImage: "play.fill").labelStyle(.titleAndIcon).frame(width: 130)
                }
            }
            .disabled(songs.isEmpty)

            // 收藏后就不再显示；取消收藏在侧边栏（歌单）或“我的收藏”（专辑）里右键
            if isCollectable && !isCollected {
                Button(action: collect) {
                    Image(systemName: "plus").frame(width: HeaderButtonStyle.height)
                }
                .help("收藏")
                .accessibilityLabel("收藏")
                .transition(.opacity)
            }
        }
        .buttonStyle(HeaderButtonStyle())
    }

    /// 专辑和别人的歌单可以收藏；自己的歌单、每日推荐没有“+”
    private var isCollectable: Bool {
        switch collection.destination {
        case .album: true
        case .playlist(let playlist): Int(playlist.id) != nil && !account.owns(playlist)
        case .artist: false
        }
    }

    /// 自己创建的歌单，歌曲的菜单里可以“从歌单中删除”。
    /// “我喜欢的音乐”不算，那里用“取消喜爱”
    private var ownPlaylist: Playlist? {
        guard case .playlist(let playlist) = collection.destination,
              account.createdPlaylists.contains(where: { $0.id == playlist.id }) else { return nil }
        return playlist
    }

    private var isLikedPlaylist: Bool {
        guard case .playlist(let playlist) = collection.destination else { return false }
        return playlist.id == account.likedPlaylist?.id
    }

    /// 列表里显示的歌，去掉了刚取消喜爱的
    private var songs: [Song] {
        let songs = detail?.songs ?? []
        return unlikedIDs.isEmpty ? songs : songs.filter { !unlikedIDs.contains($0.id) }
    }

    private var isCollected: Bool {
        switch collection.destination {
        case .album: isAlbumCollected
        case .playlist(let playlist): account.collectedPlaylists.contains { $0.id == playlist.id }
        case .artist: false
        }
    }

    private func collect() {
        guard account.isLoggedIn else {
            openLogin()
            return
        }
        Task {
            do {
                switch collection.destination {
                case .album(let album):
                    // 专辑先改界面；歌单要等账号刷新后侧边栏和按钮一起变
                    withAnimation { isAlbumCollected = true }
                    try await account.setCollected(album, true)
                case .playlist(let playlist):
                    try await account.setCollected(playlist, true)
                case .artist:
                    break
                }
                showToast(Toast(message: "已收藏“\(collection.title)”"))
            } catch {
                if case .album = collection.destination { isAlbumCollected = false }
                showToast(Toast(message: "收藏“\(collection.title)”失败：\(error.localizedDescription)", isError: true))
            }
        }
    }

    /// 播放列表封面上印着标题，专辑没有
    private var isPlaylist: Bool { collection.artworkLabel != nil }

    /// 歌单单独一列显示艺人；专辑只在有歌不是专辑艺人唱的（合辑、合唱）时才显示
    private func showsArtist(in songs: [Song]) -> Bool {
        isPlaylist || songs.contains { $0.artist != collection.subtitle }
    }

    /// 歌单显示加载后的实际数量；专辑以详情里的类型和年份为准
    private var caption: String {
        if isPlaylist, detail != nil { return "\(songs.count) 首歌曲" }
        return detail?.caption ?? collection.caption
    }

    /// 列表下方的发行日期、总时长和发行公司，和 Apple Music 一样
    private func footer(_ detail: Catalog.CollectionDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date = detail.releaseDate {
                Text(date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "zh_CN"),
                                                     timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current)))
            }
            Text("\(songs.count) 首歌曲，\(Self.totalDuration(of: songs))")
            if let company = detail.company, !company.isEmpty {
                Text(company)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private static func totalDuration(of songs: [Song]) -> String {
        let minutes = Int((songs.reduce(0) { $0 + $1.duration } / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }
}

/// 详情页顶部的按钮：浅灰底、强调色图标和文字，悬停和按下时底色加深
private struct HeaderButtonStyle: ButtonStyle {
    static let height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        HeaderButton(configuration: configuration)
    }
}

private struct HeaderButton: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(height: HeaderButtonStyle.height)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : isHovering ? 0.09 : 0.06), in: .capsule)
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

/// 简介：最多显示三行，放不下时右下角出现“更多”，点开在弹窗里看全文
private struct CollectionDescription: View {
    let title: String
    let paragraphs: [String]

    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0
    @State private var showsFullText = false

    init(title: String, text: String) {
        self.title = title
        // 网易云的简介按行分段，行首常有全角空格缩进
        paragraphs = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var isTruncated: Bool { fullHeight > shownHeight + 1 }

    var body: some View {
        let preview = paragraphs.joined(separator: " ")
        Text(preview)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            // 同样宽度下不限行数的高度，比显示出来的高就是被截断了
            .background {
                Text(preview)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
            .padding(.trailing, isTruncated ? 44 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomTrailing) {
                if isTruncated {
                    Button("更多") { showsFullText = true }
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                }
            }
            .font(.callout)
            .sheet(isPresented: $showsFullText) { fullText }
    }

    private var fullText: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).font(.system(size: 26, weight: .bold)).padding(.bottom, 6)
                    ForEach(paragraphs.indices, id: \.self) { Text(paragraphs[$0]) }
                }
                .font(.title3)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(32)
            }
            HStack {
                Spacer()
                Button("关闭") { showsFullText = false }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 620, height: 560)
        .onExitCommand { showsFullText = false }
    }
}

/// 歌曲列表，详情页和艺人页共用
struct TrackList: View {
    let songs: [Song]
    /// 歌曲来自不同艺人（歌单、合辑）时，单独一列显示艺人
    var showsArtist = false
    /// 歌曲来自不同专辑（歌单、艺人热门）时，用封面代替序号
    var showsArtwork = false
    /// 自己创建的歌单，歌曲菜单里多一项“从歌单中删除”
    var playlist: Playlist? = nil
    /// 从歌单删除成功后，由页面把这首歌拿掉
    var onRemoved: (Song) -> Void = { _ in }

    @Environment(Player.self) private var player
    @State private var hovered: Song.ID?
    @State private var selection: Song.ID?
    @State private var failure: String?

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                TrackRow(index: index + 1, song: song, showsArtist: showsArtist, showsArtwork: showsArtwork,
                         playlist: playlist, isHovering: hovered == song.id, isSelected: selection == song.id) {
                    player.play(song, in: songs)
                } onSelect: {
                    selection = song.id
                } onHover: { hovering in
                    if hovering { hovered = song.id } else if hovered == song.id { hovered = nil }
                } onRemoved: {
                    onRemoved(song)
                } onFailure: {
                    failure = $0
                }
                // 高亮行的上下不画分隔线，免得和灰底 / 强调色底叠在一起
                let hidesDivider = isHighlighted(song) || (index + 1 < songs.count && isHighlighted(songs[index + 1]))
                Divider()
                    .padding(.leading, TrackRow.dividerLeadingInset(showsArtwork: showsArtwork))
                    .padding(.trailing, TrackRow.dividerTrailingInset)
                    .opacity(hidesDivider ? 0 : 1)
            }
        }
        .alert("操作失败", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
        } message: {
            Text(failure ?? "")
        }
    }

    private func isHighlighted(_ song: Song) -> Bool {
        song.id == hovered || song.id == selection
    }
}

/// 和 Apple Music 一样：悬停时序号（或封面）上换成播放按钮、时长前出现“+”（加入歌单）、
/// 时长后出现“…”，左侧页边距里是红心。正在播放的歌显示跳动的音柱，悬停时换成暂停 / 继续。
/// 单击选中（填强调色），双击播放。
private struct TrackRow: View {
    let index: Int
    let song: Song
    let showsArtist: Bool
    let showsArtwork: Bool
    let playlist: Playlist?
    let isHovering: Bool
    let isSelected: Bool
    let onPlay: () -> Void
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    let onRemoved: () -> Void
    let onFailure: (String) -> Void

    @Environment(Player.self) private var player
    @Environment(Account.self) private var account
    @Environment(\.openLogin) private var openLogin
    @Environment(\.appearsActive) private var appearsActive

    /// 红心所在的列，伸进页面左边距
    static let likeColumnWidth: CGFloat = 28
    private static let leadingPadding: CGFloat = 6
    /// 右侧留得比分隔线多，高亮底色才能把分隔线的末端包住
    private static let trailingPadding: CGFloat = 14
    private static let artworkSize: CGFloat = 40

    /// 序号列，或者显示封面时的封面列
    private static func leadingColumnWidth(showsArtwork: Bool) -> CGFloat {
        showsArtwork ? artworkSize : 32
    }

    /// 分隔线从标题开始：左内边距 + 序号 / 封面列 + 间距
    static func dividerLeadingInset(showsArtwork: Bool) -> CGFloat {
        leadingPadding + leadingColumnWidth(showsArtwork: showsArtwork) + 12
    }
    /// 分隔线比高亮底色短一截，和 Apple Music 一样
    static let dividerTrailingInset: CGFloat = 6

    private var isCurrent: Bool { player.current?.id == song.id }
    private var isLiked: Bool { account.likedSongIDs.contains(song.id) }
    /// 选中且窗口在前台时整行填强调色、内容反白；窗口在后台时退成灰底，和系统列表一致
    private var isEmphasized: Bool { isSelected && appearsActive }
    private var accent: Color { isEmphasized ? .white : .accentColor }
    private var secondary: Color { isEmphasized ? .white.opacity(0.8) : .secondary }

    var body: some View {
        HStack(spacing: 0) {
            likeButton

            HStack(spacing: 12) {
                leading
                    .font(.callout)
                    .frame(width: Self.leadingColumnWidth(showsArtwork: showsArtwork))

                // 标题和艺人平分剩下的宽度，右边几列定宽，艺人列在每一行都对得齐
                Text(song.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isEmphasized ? Color.white : Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsArtist {
                    Text(song.artist)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 菜单弹出时鼠标已离开这一行，所以只隐藏不移除，否则菜单会被一起销毁
                addMenu
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)

                Text(song.duration.mmss)
                    .monospacedDigit()
                    .foregroundStyle(secondary)
                    .frame(width: 44, alignment: .trailing)

                SongMenuButton(song: song, playlist: playlist, onRemoved: onRemoved)
                    .foregroundStyle(accent)
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
            }
            .padding(.leading, Self.leadingPadding)
            .padding(.trailing, Self.trailingPadding)
            .frame(minHeight: showsArtwork ? 56 : 48)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background))
            // 让音柱等跟随系统选中样式的视图也知道这一行是强调色底
            .environment(\.backgroundProminence, isEmphasized ? .increased : .standard)
        }
        // 悬停区域包含左边距里的红心，所以先定好点击区域再往左挪。
        // 单击用 simultaneousGesture，不必等双击判定失败，选中没有延迟
        .contentShape(.rect)
        .gesture(TapGesture(count: 2).onEnded(onPlay))
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .contextMenu { SongMenuItems(song: song, playlist: playlist, onRemoved: onRemoved) }
        .onHover(perform: onHover)
        .padding(.leading, -Self.likeColumnWidth)
    }

    private var background: Color {
        if isEmphasized { return .accentColor }
        if isSelected { return .primary.opacity(0.1) }
        return .primary.opacity(isHovering ? 0.06 : 0)
    }

    @ViewBuilder
    private var leading: some View {
        if showsArtwork {
            ArtworkView(seed: song.artworkSeed, url: song.artworkURL, cornerRadius: 4)
                .overlay {
                    if isHovering || isCurrent {
                        ZStack {
                            Color.black.opacity(0.35)
                            playback(color: .white)
                        }
                        .clipShape(.rect(cornerRadius: 4, style: .continuous))
                        // 让音柱在深色蒙层上也用白色
                        .environment(\.backgroundProminence, .increased)
                    }
                }
        } else if isHovering || isCurrent {
            playback(color: accent)
        } else {
            Text("\(index)").foregroundStyle(secondary).monospacedDigit()
        }
    }

    /// 悬停时的播放 / 暂停按钮，不悬停时正在播放的歌显示音柱
    @ViewBuilder
    private func playback(color: Color) -> some View {
        if isHovering {
            let pauses = isCurrent && player.isPlaying
            Button {
                if isCurrent { player.togglePlayPause() } else { onPlay() }
            } label: {
                Image(systemName: pauses ? "pause.fill" : "play.fill")
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(pauses ? "暂停" : "播放")
            .accessibilityLabel(pauses ? "暂停" : "播放")
        } else {
            NowPlayingIndicator(isPlaying: player.isPlaying)
        }
    }

    private var likeButton: some View {
        Button(action: toggleLike) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tint)
                // 贴近高亮底色，离页面左边缘远一些
                .padding(.trailing, 6)
                .frame(width: Self.likeColumnWidth, height: 28, alignment: .trailing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isLiked ? "取消喜爱" : "喜爱")
        .accessibilityLabel(isLiked ? "取消喜爱" : "喜爱")
        .opacity(isLiked || isHovering ? 1 : 0)
        .allowsHitTesting(isLiked || isHovering)
    }

    @ViewBuilder
    private var addMenu: some View {
        let icon = Image(systemName: "plus")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 24, height: 28)
            .contentShape(.rect)
        if account.isLoggedIn {
            Menu {
                Section("添加到歌单") {
                    AddToPlaylistItems(song: song)
                }
            } label: {
                icon
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("添加到歌单")
            .accessibilityLabel("添加到歌单")
        } else {
            Button(action: openLogin) { icon }
                .buttonStyle(.plain)
                .help("添加到歌单")
                .accessibilityLabel("添加到歌单")
        }
    }

    private func toggleLike() {
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

/// 正在播放的跳动音柱。暂停时停在当时的高度，和 Apple Music 一样
struct NowPlayingIndicator: View {
    var isPlaying: Bool

    @Environment(\.backgroundProminence) private var backgroundProminence

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { bar in
                    Capsule().frame(width: 3, height: Self.height(of: bar, at: time))
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
        // 选中行的强调色底上改用白色
        .foregroundStyle(backgroundProminence == .increased ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
        .accessibilityLabel(isPlaying ? "正在播放" : "已暂停")
    }

    /// 每根音柱由两个频率不同的正弦波叠加，看起来没有规律；高度在 3...14 之间
    nonisolated private static func height(of bar: Int, at time: TimeInterval) -> CGFloat {
        let speeds: [Double] = [11, 14, 9.5, 12.5]
        let phase = Double(bar) * 1.7
        let wave = sin(time * speeds[bar] + phase) + sin(time * speeds[bar] * 0.53 + phase * 2)
        return 3 + 11 * CGFloat(wave + 2) / 4
    }
}
