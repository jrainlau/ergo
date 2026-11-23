import Foundation
import NaturalLanguage

/// 语言识别与语言对解析。纯逻辑，便于测试。
public nonisolated enum LanguageDetector {
    private static func isHan(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value) || (0xF900...0xFAFF).contains(s.value)
    }

    private static func isKana(_ s: Unicode.Scalar) -> Bool { (0x3040...0x30FF).contains(s.value) }
    private static func isHangul(_ s: Unicode.Scalar) -> Bool { (0xAC00...0xD7AF).contains(s.value) || (0x1100...0x11FF).contains(s.value) }

    /// 在给定的候选语言里判断文字的语言；候选为空或无法判断时返回 nil。
    public static func detect(_ text: String, among codes: [String]) -> String? {
        guard !codes.isEmpty else { return nil }
        var han = 0, kana = 0, hangul = 0, latin = 0
        for s in text.unicodeScalars {
            if isHan(s) { han += 1 }
            else if isKana(s) { kana += 1 }
            else if isHangul(s) { hangul += 1 }
            else if s.properties.isAlphabetic, s.isASCII { latin += 1 }
        }
        let zh = codes.filter { LanguageFamily.isChinese($0) }
        // 汉字为主、且没有假名/谚文：只可能是中文（或日语汉字，候选里没有日语时按中文处理）
        if han > 0, kana == 0, hangul == 0, han * 3 >= latin, !zh.isEmpty {
            if zh.count == 1 { return zh[0] }
            return recognize(text, among: zh) ?? zh[0]
        }
        if kana > 0, codes.contains("ja") { return "ja" }
        if hangul > 0, codes.contains("ko") { return "ko" }
        return recognize(text, among: codes)
    }

    private static func recognize(_ text: String, among codes: [String]) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = codes.map { NLLanguage(rawValue: $0) }
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return codes.first { $0 == dominant.rawValue } ?? codes.first { TranslateLanguage.isSame($0, dominant.rawValue) }
    }

    /// 给定检测到的语言，按语言对顺序返回要翻译成的目标语言（去重）。
    public static func targets(for detected: String, pairs: [LanguagePair]) -> [String] {
        var out: [String] = []
        for p in pairs {
            let t: String?
            if TranslateLanguage.isSame(p.a, detected) { t = p.b }
            else if TranslateLanguage.isSame(p.b, detected) { t = p.a }
            else { t = nil }
            if let t, !out.contains(t), !TranslateLanguage.isSame(t, detected) { out.append(t) }
        }
        return out
    }

    /// 语言对里出现的所有语言（去重，保持顺序）。
    public static func languages(in pairs: [LanguagePair]) -> [String] {
        var out: [String] = []
        for p in pairs { for c in [p.a, p.b] where !out.contains(c) { out.append(c) } }
        return out
    }
}

nonisolated enum LanguageFamily {
    static func isChinese(_ code: String) -> Bool { TranslateLanguage.family(code) == "zh" }
    static func isEnglish(_ code: String) -> Bool { TranslateLanguage.family(code) == "en" }
}

/// 判断一段输入是否值得拿去翻译。`canHandle` 在每次按键时同步调用，必须很快。
public nonisolated enum TranslateHeuristics {
    public static func isTranslatable(_ text: String, maxChars: Int) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, t.count <= maxChars else { return false }
        guard t.unicodeScalars.contains(where: { $0.properties.isAlphabetic }) else { return false }
        if t.contains("://") || t.hasPrefix("www.") || t.hasPrefix("/") || t.hasPrefix("~") || t.hasPrefix("=") { return false }
        // 邮箱
        if !t.contains(" "), t.contains("@") { return false }
        // 像算式：有数字，又有运算符
        if t.contains(where: \.isNumber), t.contains(where: { "+*/^=%".contains($0) }) { return false }
        return true
    }
}
