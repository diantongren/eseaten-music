import SwiftUI

/// 操作结果的轻提示，浮在播放条上方，几秒后自己消失
struct Toast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    var isError = false
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        Label {
            Text(toast.message).lineLimit(1)
        } icon: {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 16)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
    }
}

extension EnvironmentValues {
    /// 弹出一条轻提示
    @Entry var showToast: @MainActor (Toast) -> Void = { _ in }
}
