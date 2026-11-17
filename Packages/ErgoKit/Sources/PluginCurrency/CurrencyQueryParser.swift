import Foundation
import ErgoPluginSupport

public nonisolated struct ParsedCurrencyQuery: Equatable, Sendable {
    public var amount: Double
    public var source: String
    public var target: String?
}

public nonisolated enum CurrencyQueryParser {
    /// 名称 / 文字别名 → ISO 代码（key 为小写）。
    static let names: [String: String] = [
        "人民币": "CNY", "rmb": "CNY", "元": "CNY", "块": "CNY", "人民币元": "CNY", "cny": "CNY",
        "美元": "USD", "美金": "USD", "刀": "USD", "usd": "USD",
        "欧元": "EUR", "eur": "EUR",
        "英镑": "GBP", "gbp": "GBP",
        "韩元": "KRW", "韩币": "KRW", "krw": "KRW",
        "港币": "HKD", "港元": "HKD", "hkd": "HKD",
        "日元": "JPY", "日币": "JPY", "円": "JPY", "jpy": "JPY",
        "加元": "CAD", "加币": "CAD", "澳元": "AUD", "澳币": "AUD", "新币": "SGD", "新加坡元": "SGD",
        "瑞士法郎": "CHF", "新台币": "TWD", "台币": "TWD", "泰铢": "THB", "卢布": "RUB", "印度卢比": "INR",
        "新西兰元": "NZD", "林吉特": "MYR", "澳门元": "MOP",
    ]

    /// 前缀符号（按长度从长到短匹配）。
    static func symbols(yenIsJPY: Bool) -> [(String, String)] {
        [("hk$", "HKD"), ("¥", yenIsJPY ? "JPY" : "CNY"), ("￥", yenIsJPY ? "JPY" : "CNY"),
         ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("₩", "KRW")]
    }

    static let separators = ["兑换", "转换", "to", "in", "=", "转", "换", "兑"]

    public static func parse(_ text: String, knownCodes: Set<String>, yenIsJPY: Bool = false) -> ParsedCurrencyQuery? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 80 else { return nil }
        let lower = s.lowercased()

        // 1. 前缀符号
        for (sym, code) in symbols(yenIsJPY: yenIsJPY) where lower.hasPrefix(sym) {
            guard knownCodes.contains(code) else { continue }
            let rest = String(s.dropFirst(sym.count)).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return ParsedCurrencyQuery(amount: 1, source: code, target: nil) }
            if let v = amount(rest) { return ParsedCurrencyQuery(amount: v, source: code, target: nil) }
            // $100 to cny
            for i in splitPoints(rest) {
                let left = String(rest[..<i]), right = String(rest[i...]).trimmingCharacters(in: .whitespaces)
                guard let v = amount(left), let t = target(afterSeparatorIn: right, known: knownCodes, yenIsJPY: yenIsJPY) else { continue }
                return ParsedCurrencyQuery(amount: v, source: code, target: t)
            }
            return nil
        }

        // 2. 金额 + 单位 [+ 分隔词 + 目标]
        for i in splitPoints(s) {
            let left = String(s[..<i])
            guard let v = amount(left) else { continue }
            let right = String(s[i...]).trimmingCharacters(in: .whitespaces)
            guard !right.isEmpty else { continue }
            if let src = resolve(right, known: knownCodes, yenIsJPY: yenIsJPY) {
                return ParsedCurrencyQuery(amount: v, source: src, target: nil)
            }
            for sep in separators {
                var from = right.startIndex
                while let r = right.range(of: sep, options: .caseInsensitive, range: from..<right.endIndex) {
                    let a = String(right[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let b = String(right[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if let src = resolve(a, known: knownCodes, yenIsJPY: yenIsJPY), let tgt = resolve(b, known: knownCodes, yenIsJPY: yenIsJPY) {
                        return ParsedCurrencyQuery(amount: v, source: src, target: tgt)
                    }
                    from = r.upperBound
                }
            }
        }
        return nil
    }

    // MARK: helpers

    /// 所有可能的“金额 | 单位”分割下标（从左到右）。
    private static func splitPoints(_ s: String) -> [String.Index] {
        var out: [String.Index] = []
        var i = s.startIndex
        while i < s.endIndex {
            i = s.index(after: i)
            out.append(i)
        }
        return out.dropLast().map { $0 }   // 去掉 endIndex（右侧为空）
    }

    private static func amount(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.contains(where: \.isNumber) else { return nil }
        guard let v = try? MathExpression.evaluate(t), v.isFinite, v >= 0 else { return nil }
        return v
    }

    private static func target(afterSeparatorIn s: String, known: Set<String>, yenIsJPY: Bool) -> String? {
        for sep in separators where s.lowercased().hasPrefix(sep) {
            let rest = String(s.dropFirst(sep.count)).trimmingCharacters(in: .whitespaces)
            if let c = resolve(rest, known: known, yenIsJPY: yenIsJPY) { return c }
        }
        return nil
    }

    /// 把一个货币记号解析为 ISO 代码。
    public static func resolve(_ token: String, known: Set<String>, yenIsJPY: Bool = false) -> String? {
        let t = token.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let l = t.lowercased()
        if let (_, code) = symbols(yenIsJPY: yenIsJPY).first(where: { $0.0 == l }), known.contains(code) { return code }
        if let c = names[l], known.contains(c) { return c }
        let up = t.uppercased()
        if up.count == 3, up.allSatisfy({ $0.isASCII && $0.isLetter }), known.contains(up) { return up }
        return nil
    }
}
