import SwiftUI

@main
struct EseatenMusicApp: App {
    @State private var player = Player()
    @State private var account = Account()

    init() {
        // 封面图走 URLCache，默认容量太小，滚动货架时会反复下载
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
                .environment(account)
                .frame(minWidth: 960, minHeight: 620)
                .task { await account.restore() }
        }
        .defaultSize(width: 1240, height: 800)
        // 标题由页面内的大标题承担，工具栏不重复显示
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandMenu("控制") {
                Button(player.isPlaying ? "暂停" : "播放") { player.togglePlayPause() }
                Button("下一首") { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("上一首") { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }
    }
}
