import Foundation

public nonisolated struct ExpansionContext: Sendable {
    public var now: Date
    public var clipboard: String
    public var uuid: @Sendable () -> String
    public var calendar: Calendar

    public init(now: Date = Date(), clipboard: String = "", uuid: @escaping @Sendable () -> String = { UUID().uuidString }, calendar: Calendar = .current) {
        self.now = now
        self.clipboard = clipboard
        self.uuid = uuid
        self.calendar = calendar
    }
}

public nonisolated struct ExpandedSnippet: Equatable, Sendable {
    public var text: String
    /// 粘贴后需要向左移动的字符数（对应 {cursor}）；nil 表示不移动。
    public var cursorBack: Int?
}

public nonisolated enum SnippetExpander {
    public static let placeholders: [(token: String, title: String)] = [
        ("{date}", "日期 yyyy-MM-dd"), ("{time}", "时间 HH:mm"), ("{datetime}", "日期时间"),
        ("{date:yyyy年M月d日}", "自定义日期格式"), ("{clipboard}", "剪贴板文本"), ("{uuid}", "随机 UUID"), ("{cursor}", "光标位置"),
    ]

    public static func expand(_ template: String, context: ExpansionContext = ExpansionContext()) -> ExpandedSnippet {
        var out = ""
        var cursorAt: Int?
        var outCount = 0
        func append(_ s: String) { out += s; outCount += s.count }

        let chars = Array(template)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "{", i + 1 < chars.count, chars[i + 1] == "{" { append("{"); i += 2; continue }
            if c == "}", i + 1 < chars.count, chars[i + 1] == "}" { append("}"); i += 2; continue }
            if c == "{", let close = chars[(i + 1)...].firstIndex(of: "}") {
                let token = String(chars[(i + 1)..<close])
                if let v = value(for: token, context: context) {
                    if v == "\u{0}cursor" {
                        if cursorAt == nil { cursorAt = outCount }
                    } else {
                        append(v)
                    }
                    i = close + 1
                    continue
                }
            }
            append(String(c))
            i += 1
        }
        return ExpandedSnippet(text: out, cursorBack: cursorAt.map { outCount - $0 }.flatMap { $0 > 0 ? $0 : nil })
    }

    private static func value(for token: String, context: ExpansionContext) -> String? {
        switch token {
        case "date": return format("yyyy-MM-dd", context)
        case "time": return format("HH:mm", context)
        case "datetime": return format("yyyy-MM-dd HH:mm", context)
        case "clipboard": return context.clipboard
        case "uuid": return context.uuid()
        case "cursor": return "\u{0}cursor"
        default:
            if token.hasPrefix("date:") {
                let fmt = String(token.dropFirst(5))
                return fmt.isEmpty ? nil : format(fmt, context)
            }
            return nil
        }
    }

    private static func format(_ pattern: String, _ ctx: ExpansionContext) -> String {
        let f = DateFormatter()
        f.calendar = ctx.calendar
        f.timeZone = ctx.calendar.timeZone
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = pattern
        return f.string(from: ctx.now)
    }
}
