import CoreImage.CIFilterBuiltins
import SwiftUI

/// 网易云扫码登录：生成二维码，每 2 秒轮询一次扫码状态
struct LoginSheet: View {
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var qrImage: NSImage?
    @State private var status = "正在获取二维码…"
    @State private var expired = false
    /// 改变它来重新生成二维码
    @State private var round = 0

    var body: some View {
        VStack(spacing: 18) {
            Text("登录网易云音乐").font(.title2.bold())

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
                if let qrImage {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .padding(12)
                        .opacity(expired ? 0.15 : 1)
                } else {
                    ProgressView()
                }
                if expired {
                    Button("刷新二维码") { round += 1 }
                        .buttonStyle(.glassProminent)
                }
            }
            .frame(width: 220, height: 220)

            Text(status).font(.callout).foregroundStyle(.secondary)
            Text("打开网易云音乐 App，在“我的”页面右上角扫一扫").font(.caption).foregroundStyle(.tertiary)

            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 340)
        .task(id: round) { await poll() }
    }

    private func poll() async {
        expired = false
        qrImage = nil
        status = "正在获取二维码…"
        do {
            let key = try await NeteaseAPI.qrKey()
            qrImage = Self.qrCode(NeteaseAPI.qrContent(for: key))
            status = "请使用网易云音乐 App 扫码"
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(2))
                switch try await NeteaseAPI.qrCheck(key: key) {
                case .waiting:
                    break
                case .scanned(let nickname):
                    status = "\(nickname.map { "\($0)，" } ?? "")请在手机上确认登录"
                case .expired:
                    expired = true
                    status = "二维码已过期"
                    return
                case .authorized:
                    status = "登录成功"
                    await account.reload()
                    dismiss()
                    return
                }
            }
        } catch is CancellationError {
        } catch {
            expired = true
            status = error.localizedDescription
        }
    }

    private static func qrCode(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: output.extent.size)
    }
}
