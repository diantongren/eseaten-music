import Foundation

/// 一首歌的歌词
struct Lyrics: Sendable {
    struct Line: Identifiable, Sendable {
        let id: Int
        /// 开始时间；没有时间轴的歌词为 nil
        let time: TimeInterval?
        let text: String
        var translation: String?
    }

    enum Status: Sendable {
        case lines([Line])
        /// 网易云标记为纯音乐
        case instrumental
        case unavailable
    }

    let status: Status

    var isSynced: Bool {
        guard case .lines(let lines) = status else { return false }
        return lines.first?.time != nil
    }

    /// 当前时间对应的行：最后一行开始时间不晚于 `time` 的
    func lineIndex(at time: TimeInterval) -> Int? {
        guard case .lines(let lines) = status else { return nil }
        return lines.lastIndex { ($0.time ?? .infinity) <= time }
    }
}

extension Lyrics {
    init(_ lyric: NeteaseLyric) {
        if lyric.nolyric == true {
            status = .instrumental
            return
        }
        let original = Self.parse(lyric.lrc?.lyric ?? "")
        guard !original.isEmpty else {
            status = .unavailable
            return
        }
        // 翻译按时间对上原文
        let translations = Dictionary(
            Self.parse(lyric.tlyric?.lyric ?? "").compactMap { line in line.time.map { (Self.key($0), line.text) } },
            uniquingKeysWith: { first, _ in first }
        )
        var lines = original.enumerated().map { index, line in
            Line(id: index, time: line.time, text: line.text,
                 translation: line.time.flatMap { translations[Self.key($0)] })
        }
        // 只有一行“纯音乐，请欣赏”之类的也当作纯音乐
        if lines.count == 1, lines[0].text.contains("纯音乐") {
            status = .instrumental
            return
        }
        lines.removeAll { $0.text.isEmpty && $0.translation == nil }
        status = .lines(lines.enumerated().map { Line(id: $0, time: $1.time, text: $1.text, translation: $1.translation) })
    }

    private static func key(_ time: TimeInterval) -> Int { Int((time * 100).rounded()) }

    // `[mm:ss.xx]` 时间标签，一行可以有多个
    nonisolated(unsafe) private static let tag = /\[(\d+):(\d+)(?:[.:](\d+))?\]/

    /// 解析 LRC。网易云开头几行可能是 JSON（作词作曲信息），也一并转成普通行。
    /// 整段都没有时间标签时按无时间轴的纯文本处理。
    static func parse(_ lrc: String) -> [(time: TimeInterval?, text: String)] {
        var timed: [(time: TimeInterval?, text: String)] = []
        var plain: [(time: TimeInterval?, text: String)] = []

        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("{"), let credit = credit(line) {
                timed.append(credit)
                continue
            }
            let matches = line.matches(of: tag)
            guard let last = matches.last else {
                // 跳过 [ar:xxx] 这种元数据
                if !line.hasPrefix("[") && !line.isEmpty { plain.append((nil, line)) }
                continue
            }
            let text = line[last.range.upperBound...].trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(match.1) ?? 0
                let seconds = Double(match.2) ?? 0
                let fraction = match.3.map { Double("0.\($0)") ?? 0 } ?? 0
                timed.append((minutes * 60 + seconds + fraction, text))
            }
        }
        if timed.isEmpty { return plain }
        return timed.sorted { ($0.time ?? 0) < ($1.time ?? 0) }
    }

    /// `{"t":0,"c":[{"tx":"作词: "},{"tx":"某人"}]}`
    private static func credit(_ line: String) -> (time: TimeInterval?, text: String)? {
        struct Credit: Decodable {
            struct Part: Decodable { let tx: String }
            let t: Double
            let c: [Part]
        }
        guard let credit = try? JSONDecoder().decode(Credit.self, from: Data(line.utf8)) else { return nil }
        return (credit.t / 1000, credit.c.map(\.tx).joined())
    }
}
