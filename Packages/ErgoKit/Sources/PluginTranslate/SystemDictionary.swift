import Foundation
import CoreServices

// MARK: - 词条解析（纯逻辑）

/// 解析「牛津英汉汉英词典」的词条文本，提取简明释义。
public nonisolated enum DictionaryParser {
    private static let senseMarkers = "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"

    private static let partsOfSpeech: [String] = [
        "noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction", "exclamation",
        "interjection", "numeral", "measure word", "classifier", "particle", "auxiliary verb", "prefix",
        "suffix", "abbreviation", "idiom", "onomatopoeia", "modal verb", "determiner", "plural", "phrasal verb",
    ]

    /// 返回 nil 表示这条结果不是我们要的（例如英文输入却匹配到了拼音词条）。
    public static func parse(_ raw: String, term: String, sourceIsChinese: Bool) -> TranslationOutput? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let summary = sourceIsChinese ? chineseToEnglish(text, term: term) : englishToChinese(text, term: term)
        guard let summary, !summary.isEmpty else { return nil }
        return TranslationOutput(text: summary, detail: text)
    }

    // 英 → 中："hello | BrE …, AmE … | A. noun 问候 wènhòu B. exclamation ① (greeting) 你好 nǐ hǎo; …"
    static func englishToChinese(_ text: String, term: String) -> String? {
        // 英文输入却以汉字开头，是拼音匹配到了汉字词条（如 run → 闰 rùn）
        guard let first = text.unicodeScalars.first, !isHan(first) else { return nil }
        let parts = text.components(separatedBy: " | ")
        guard parts.count >= 2 else { return nil }
        var body = parts.count >= 3 ? parts[2...].joined(separator: " | ") : parts[1]
        body = stripExamples(body)
        body = stripBrackets(body)
        let glosses = unique(matches(#"[\u3400-\u4DBF\u4E00-\u9FFF]+"#, in: body))
        guard !glosses.isEmpty else { return nil }
        return glosses.prefix(6).joined(separator: "；")
    }

    // 中 → 英："世界 shìjiè noun ① （一切事物） world▸ 创造新世界 create a new world ② …"
    static func chineseToEnglish(_ text: String, term: String) -> String? {
        guard text.hasPrefix(term) else { return nil }
        var body = String(text.dropFirst(term.count)).trimmingCharacters(in: .whitespaces)
        body = stripExamples(body)
        body = stripBrackets(body)
        body = skipPronunciation(body)
        // 按释义序号 / A. B. 切分
        var normalized = body
        for ch in senseMarkers { normalized = normalized.replacingOccurrences(of: String(ch), with: "\u{1}") }
        normalized = normalized.replacingOccurrences(of: #"(^|\s)[A-D]\.\s"#, with: "\u{1}", options: .regularExpression)
        var glosses: [String] = []
        for var seg in normalized.components(separatedBy: "\u{1}") {
            if let r = seg.range(of: "→") { seg = String(seg[..<r.lowerBound]) }
            seg = seg.replacingOccurrences(of: #"[\u3400-\u4DBF\u4E00-\u9FFF，。、；：！？]+"#, with: " ", options: .regularExpression)
            seg = stripLeadingPartOfSpeech(seg)
            seg = seg.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ;,.；，"))
            if !seg.isEmpty { glosses.append(seg) }
        }
        let result = unique(glosses)
        guard !result.isEmpty else { return nil }
        return result.prefix(4).joined(separator: "; ")
    }

    // MARK: 工具

    private static func isHan(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value) || (0x3400...0x4DBF).contains(s.value)
    }

    /// 去掉例句：从 ▸ 开始，到下一个释义序号或 “A.” 之前。
    static func stripExamples(_ s: String) -> String {
        s.replacingOccurrences(of: "▸(?:(?!\\s[A-D]\\.\\s)[^\(senseMarkers)])*", with: " ", options: .regularExpression)
    }

    /// 去掉括号里的语境说明，如 (greeting)、（一切事物）、［Buddhism］、«midwife»。
    static func stripBrackets(_ s: String) -> String {
        var out = s
        for pattern in [#"\([^)]*\)"#, #"（[^）]*）"#, #"\[[^\]]*\]"#, #"［[^］]*］"#, #"«[^»]*»"#] {
            out = out.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return out
    }

    /// 跳过读音：中文词条里，词头后面是拼音，直到词性或第一个释义序号。
    static func skipPronunciation(_ s: String) -> String {
        let tokens = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return s }
        for (i, t) in tokens.enumerated() {
            if partsOfSpeech.contains(t) || t.first.map({ senseMarkers.contains($0) }) == true {
                return tokens[i...].joined(separator: " ")
            }
        }
        return tokens.dropFirst().joined(separator: " ")
    }

    static func stripLeadingPartOfSpeech(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for pos in partsOfSpeech where out.hasPrefix(pos + " ") || out == pos {
                out = String(out.dropFirst(pos.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return out
    }

    private static func matches(_ pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

// MARK: - 系统词典访问

/// 通过 DictionaryServices 查询 macOS 自带的词典。
/// 枚举词典用到了未公开的符号（运行时 dlsym 查找，找不到就当作不可用），查词本身用公开的 `DCSCopyTextDefinition`。
public nonisolated final class SystemDictionary: @unchecked Sendable {
    public static let shared = SystemDictionary()
    /// 牛津英汉汉英词典（Oxford Chinese Dictionary）。
    public static let oxfordChineseEnglish = "com.apple.dictionary.zh_CN-en.OCD"

    private typealias AvailableFn = @convention(c) () -> Unmanaged<CFSet>?
    private typealias IdentifierFn = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>?

    private let lock = NSLock()
    private var dictionaries: [String: AnyObject]?
    private var installedCache: (date: Date, ids: Set<String>)?

    private func loadDictionaries() -> [String: AnyObject] {
        lock.lock(); defer { lock.unlock() }
        if let d = dictionaries { return d }
        var map: [String: AnyObject] = [:]
        let handle = dlopen(nil, RTLD_NOW)
        if let a = dlsym(handle, "DCSCopyAvailableDictionaries"), let i = dlsym(handle, "DCSDictionaryGetIdentifier"),
           let set = unsafeBitCast(a, to: AvailableFn.self)()?.takeRetainedValue() {
            let idFn = unsafeBitCast(i, to: IdentifierFn.self)
            for obj in set as NSSet {
                let o = obj as AnyObject
                let ptr = UnsafeRawPointer(Unmanaged.passUnretained(o).toOpaque())
                if let id = idFn(ptr)?.takeUnretainedValue() as String? { map[id] = o }
            }
        }
        dictionaries = map
        return map
    }

    /// 词典是否已经安装到本机（在“词典” App 的设置里勾选后系统会下载）。
    public func isInstalled(_ identifier: String = SystemDictionary.oxfordChineseEnglish) -> Bool {
        installedIdentifiers().contains(identifier) && loadDictionaries()[identifier] != nil
    }

    public func invalidateCache() {
        lock.lock(); installedCache = nil; lock.unlock()
    }

    private func installedIdentifiers() -> Set<String> {
        lock.lock()
        if let c = installedCache, Date().timeIntervalSince(c.date) < 30 { lock.unlock(); return c.ids }
        lock.unlock()
        var ids = Set<String>()
        let fm = FileManager.default
        var roots = [URL(fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_DictionaryServices_dictionary3macOS")]
        roots.append(URL(fileURLWithPath: "/Library/Dictionaries"))
        roots.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Dictionaries"))
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                let candidates = [entry] + ((try? fm.contentsOfDirectory(at: entry.appendingPathComponent("AssetData"), includingPropertiesForKeys: nil)) ?? [])
                for c in candidates where c.pathExtension == "dictionary" {
                    let plist = c.appendingPathComponent("Contents/Info.plist")
                    if let data = try? Data(contentsOf: plist),
                       let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let id = obj["CFBundleIdentifier"] as? String {
                        ids.insert(id)
                    }
                }
            }
        }
        lock.lock(); installedCache = (Date(), ids); lock.unlock()
        return ids
    }

    /// 同步查词，会读磁盘，不要在主线程调用。
    public func lookup(_ term: String, in identifier: String = SystemDictionary.oxfordChineseEnglish) -> String? {
        guard let dict = loadDictionaries()[identifier] else { return nil }
        let cf = term as CFString
        let ptr = Unmanaged.passUnretained(dict).toOpaque()
        let ref = unsafeBitCast(ptr, to: DCSDictionary.self)
        guard let r = DCSCopyTextDefinition(ref, cf, CFRange(location: 0, length: CFStringGetLength(cf))) else { return nil }
        return r.takeRetainedValue() as String
    }
}

// MARK: - 引擎

/// 牛津英汉汉英词典：只处理中英单词与短语，查不到就返回 nil，交给后面的引擎。
public nonisolated struct DictionaryEngine: TranslationEngine {
    public let id = EngineID.dictionary
    public let name = "牛津英汉汉英词典"

    public init() {}

    public func translate(_ text: String, from: String, to: String) async throws -> TranslationOutput? {
        let sourceIsChinese = LanguageFamily.isChinese(from)
        guard (sourceIsChinese && LanguageFamily.isEnglish(to)) || (LanguageFamily.isEnglish(from) && LanguageFamily.isChinese(to)) else { return nil }
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 词典只收词和短语
        guard !term.isEmpty, term.count <= 40, term.split(whereSeparator: \.isWhitespace).count <= 5, !term.contains("\n") else { return nil }
        guard SystemDictionary.shared.isInstalled() else {
            throw TranslateError.unavailable("未安装「牛津英汉汉英词典」，请在“词典”App 的设置里勾选并下载")
        }
        let raw = await Task.detached(priority: .userInitiated) { SystemDictionary.shared.lookup(term) }.value
        guard let raw else { return nil }
        return DictionaryParser.parse(raw, term: term, sourceIsChinese: sourceIsChinese)
    }
}
