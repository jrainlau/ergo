import Foundation

public enum FuzzyMatcher {
    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static let separators: Set<Character> = [" ", "-", "_", ".", "/", "(", ")", "·"]

    /// 单词首字母序列，按空白、分隔符与驼峰切分。
    static func wordInitials(_ s: String) -> String {
        var result = ""
        var prev: Character? = nil
        for ch in s {
            if separators.contains(ch) { prev = ch; continue }
            let isStart: Bool
            if let p = prev {
                isStart = separators.contains(p) || (p.isLowercase && ch.isUppercase)
            } else {
                isStart = true
            }
            if isStart, ch.isLetter || ch.isNumber { result.append(contentsOf: String(ch).lowercased()) }
            prev = ch
        }
        return result
    }

    /// 返回 0...1 的匹配分；不匹配返回 nil。
    public static func score(query: String, candidate: String, pinyinFull: String? = nil, pinyinInitials: String? = nil) -> Double? {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return nil }
        let c = fold(candidate)
        guard !c.isEmpty else { return nil }

        var best: Double? = nil
        func take(_ v: Double) { if best == nil || v > best! { best = v } }

        if c == q { return 1.0 }
        if c.hasPrefix(q) {
            take(0.9 + 0.05 * Double(q.count) / Double(c.count))
        }
        let initials = wordInitials(candidate)
        if q.count >= 2, initials.hasPrefix(q) { take(0.8) }

        if let pf = pinyinFull, !pf.isEmpty, pf.hasPrefix(q) { take(0.85) }
        if let pi = pinyinInitials, !pi.isEmpty, q.count >= 2, pi.hasPrefix(q) { take(0.8) }

        if let r = c.range(of: q) {
            if r.lowerBound == c.startIndex {
                take(0.9)
            } else {
                let before = c[c.index(before: r.lowerBound)]
                take(separators.contains(before) ? 0.7 : 0.6)
            }
        }

        if best == nil {
            // 子序列
            var qi = q.startIndex
            var first: Int? = nil
            var last = 0
            for (idx, ch) in c.enumerated() {
                if qi < q.endIndex, ch == q[qi] {
                    if first == nil { first = idx }
                    last = idx
                    qi = q.index(after: qi)
                }
            }
            if qi == q.endIndex, let f = first {
                let span = last - f + 1
                take(0.3 + 0.3 * Double(q.count) / Double(span))
            }
        }
        return best
    }
}
