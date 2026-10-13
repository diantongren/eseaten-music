import SwiftUI

/// 封面：有图片地址时加载真实封面，加载中或没有图片时显示种子生成的渐变
struct ArtworkView: View {
    let seed: Int
    var url: URL? = nil
    var cornerRadius: CGFloat = 8
    var label: String?

    var body: some View {
        placeholder
            .overlay {
                if let url {
                    GeometryReader { geo in
                        AsyncImage(url: url.neteaseThumbnail(points: geo.size.width)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.clear
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
            }
    }

    /// 有真实封面时用中性灰占位，避免渐变闪一下
    @ViewBuilder
    private var placeholder: some View {
        if url != nil {
            Rectangle().fill(.quaternary)
        } else {
            gradient
        }
    }

    @ViewBuilder
    private var gradient: some View {
        let hue = Double(seed % 360) / 360
        let accentHue = (hue + 0.12 + Double(seed % 5) * 0.05).truncatingRemainder(dividingBy: 1)
        let glowX = 0.2 + Double(seed % 7) * 0.1
        let glowY = 0.15 + Double(seed % 11) * 0.06

        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color(hue: hue, saturation: 0.55, brightness: 0.92),
                        Color(hue: hue, saturation: 0.85, brightness: 0.38),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(hue: accentHue, saturation: 0.7, brightness: 1).opacity(0.85), .clear],
                    center: UnitPoint(x: glowX, y: glowY),
                    startRadius: 0, endRadius: geo.size.width * 0.75
                )
                if let label {
                    Text(label)
                        .font(.system(size: geo.size.width * 0.12, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(geo.size.width * 0.08)
                }
            }
        }
    }
}

#Preview {
    HStack {
        ArtworkView(seed: 42).frame(width: 160)
        ArtworkView(seed: 917, label: "今日推荐").frame(width: 160)
    }
    .padding()
}
