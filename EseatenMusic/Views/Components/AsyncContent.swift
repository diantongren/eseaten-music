import SwiftUI

/// 异步加载数据再显示：加载中转圈，失败时给出原因和重试按钮。
/// `id` 变化时重新加载，加载期间保留上一次的内容（搜索时不闪）。
struct AsyncContent<Value, Content: View>: View {
    var id: AnyHashable = 0
    let load: @MainActor () async throws -> Value
    @ViewBuilder let content: (Value) -> Content

    @State private var value: Value?
    @State private var error: (any Error)?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let value {
                content(value)
            } else if let error {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("重试") { attempt += 1 }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: [id, AnyHashable(attempt)]) {
            do {
                let loaded = try await load()
                value = loaded
                error = nil
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
                value = nil
            }
        }
    }
}

/// 资料库页面在未登录时的占位
struct LoginPrompt: View {
    let title: String
    @Environment(\.openLogin) private var openLogin

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "person.crop.circle")
        } description: {
            Text("登录网易云音乐后查看")
        } actions: {
            Button("登录") { openLogin() }
                .buttonStyle(.glassProminent)
        }
        .navigationTitle(title)
    }
}

extension EnvironmentValues {
    /// 打开登录面板
    @Entry var openLogin: @MainActor () -> Void = {}
    /// 推入一个页面。播放条在 NavigationStack 外面，用它跳转
    @Entry var navigate: @MainActor (Destination) -> Void = { _ in }
}
