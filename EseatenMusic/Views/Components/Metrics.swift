import SwiftUI

enum Metrics {
    /// 页面左右边距
    static let margin: CGFloat = 40
    /// 播放条胶囊的高度
    static let playerBarHeight: CGFloat = 60
    /// 播放条内容到胶囊左右边缘的距离
    static let playerBarPadding: CGFloat = 20
    /// 播放条与窗口底边的距离
    static let playerBarBottomMargin: CGFloat = 14
    /// 右侧歌词 / 待播清单面板的宽度
    static let sidePanelWidth: CGFloat = 320
    /// 页面底部要让出的高度：播放条 + 底边距 + 一点呼吸空间
    static var playerBarClearance: CGFloat { playerBarHeight + playerBarBottomMargin + 8 }
}
