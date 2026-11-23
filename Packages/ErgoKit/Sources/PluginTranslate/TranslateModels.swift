import Foundation

// MARK: - 语言

public nonisolated struct TranslateLanguage: Hashable, Identifiable, Sendable {
    /// 同时是 `NLLanguage.rawValue` 和 `Locale.Language` 的标识符。
    public let code: String
    public let name: String
    public var id: String { code }

    public static let all: [TranslateLanguage] = [
        .init(code: "zh-Hans", name: "简体中文"),
        .init(code: "zh-Hant", name: "繁体中文"),
        .init(code: "en", name: "英语"),
        .init(code: "ja", name: "日语"),
        .init(code: "ko", name: "韩语"),
        .init(code: "fr", name: "法语"),
        .init(code: "de", name: "德语"),
        .init(code: "es", name: "西班牙语"),
        .init(code: "it", name: "意大利语"),
        .init(code: "pt", name: "葡萄牙语"),
        .init(code: "ru", name: "俄语"),
        .init(code: "ar", name: "阿拉伯语"),
        .init(code: "th", name: "泰语"),
        .init(code: "vi", name: "越南语"),
        .init(code: "id", name: "印尼语"),
        .init(code: "tr", name: "土耳其语"),
        .init(code: "nl", name: "荷兰语"),
        .init(code: "pl", name: "波兰语"),
        .init(code: "uk", name: "乌克兰语"),
        .init(code: "hi", name: "印地语"),
    ]

    public static func name(of code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }

    /// 语言族：`zh-Hans` 与 `zh-Hant` 同属 `zh`。
    public static func family(_ code: String) -> String {
        code.split(separator: "-").first.map(String.init) ?? code
    }

    public static func isSame(_ a: String, _ b: String) -> Bool {
        a == b || family(a) == family(b)
    }
}

/// 一对互译的语言：输入属于其中一种，就译成另一种。
public nonisolated struct LanguagePair: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var a: String
    public var b: String
    public var id: String { "\(a)<>\(b)" }
    public init(a: String, b: String) { self.a = a; self.b = b }

    public static let chineseEnglish = LanguagePair(a: "zh-Hans", b: "en")
}

// MARK: - 大模型引擎

public nonisolated enum LLMKind: String, Codable, CaseIterable, Sendable {
    case openAICompatible, anthropic
    public var title: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容"
        case .anthropic: "Anthropic"
        }
    }
}

public nonisolated struct LLMEngineConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: LLMKind
    public var baseURL: String
    public var model: String
    /// 附加提示词，例如“使用口语化的表达”。留空则只用内置提示词。
    public var extraPrompt: String
    public var requiresKey: Bool
    public var enabled: Bool

    public init(id: String = UUID().uuidString, name: String, kind: LLMKind = .openAICompatible, baseURL: String, model: String = "", extraPrompt: String = "", requiresKey: Bool = true, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.extraPrompt = extraPrompt
        self.requiresKey = requiresKey
        self.enabled = enabled
    }

    public var engineID: String { "llm.\(id)" }
    public var keyAccount: String { "translate.llm.\(id)" }
}

public nonisolated struct LLMPreset: Sendable {
    public var name: String
    public var kind: LLMKind
    public var baseURL: String
    public var model: String
    public var requiresKey = true

    public static let all: [LLMPreset] = [
        LLMPreset(name: "OpenAI", kind: .openAICompatible, baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini"),
        LLMPreset(name: "Anthropic", kind: .anthropic, baseURL: "https://api.anthropic.com/v1", model: "claude-3-5-haiku-latest"),
        LLMPreset(name: "DeepSeek", kind: .openAICompatible, baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat"),
        LLMPreset(name: "Moonshot", kind: .openAICompatible, baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k"),
        LLMPreset(name: "通义千问", kind: .openAICompatible, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-turbo"),
        LLMPreset(name: "智谱", kind: .openAICompatible, baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash"),
        LLMPreset(name: "SiliconFlow", kind: .openAICompatible, baseURL: "https://api.siliconflow.cn/v1", model: ""),
        LLMPreset(name: "Ollama（本地）", kind: .openAICompatible, baseURL: "http://localhost:11434/v1", model: "", requiresKey: false),
        LLMPreset(name: "自定义", kind: .openAICompatible, baseURL: "", model: ""),
    ]
}

// MARK: - 设置

public nonisolated enum EngineID {
    public static let dictionary = "dictionary"
    public static let system = "system"
}

public nonisolated struct TranslateSettings: Codable, Equatable, Sendable {
    /// 互译的语言对。默认只有中英。
    public var pairs: [LanguagePair] = [.chineseEnglish]
    /// 在主搜索框里输入文字时自动翻译（没有其他结果时排第一，有结果时排在后面）。
    public var autoInSearch = true
    /// 主搜索框自动翻译的最大字符数，超过就不翻译。
    public var searchMaxChars = 200
    /// 系统词典（牛津英汉汉英词典），仅中英单词与短语。
    public var useDictionary = true
    /// 系统自带的离线翻译（需要在系统里下载语言包）。
    public var useSystemTranslation = true
    public var llmEngines: [LLMEngineConfig] = []
    /// 主搜索框自动翻译时是否也调用大模型（会消耗 token，默认关闭；`translate` 关键词里始终可用）。
    public var llmInSearch = false
    /// 引擎优先级，排在前面的先试，取第一个成功的结果。
    public var engineOrder: [String] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case pairs, autoInSearch, searchMaxChars, useDictionary, useSystemTranslation, llmEngines, llmInSearch, engineOrder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TranslateSettings()
        pairs = try c.decodeIfPresent([LanguagePair].self, forKey: .pairs) ?? d.pairs
        autoInSearch = try c.decodeIfPresent(Bool.self, forKey: .autoInSearch) ?? d.autoInSearch
        searchMaxChars = try c.decodeIfPresent(Int.self, forKey: .searchMaxChars) ?? d.searchMaxChars
        useDictionary = try c.decodeIfPresent(Bool.self, forKey: .useDictionary) ?? d.useDictionary
        useSystemTranslation = try c.decodeIfPresent(Bool.self, forKey: .useSystemTranslation) ?? d.useSystemTranslation
        llmEngines = try c.decodeIfPresent([LLMEngineConfig].self, forKey: .llmEngines) ?? d.llmEngines
        llmInSearch = try c.decodeIfPresent(Bool.self, forKey: .llmInSearch) ?? d.llmInSearch
        engineOrder = try c.decodeIfPresent([String].self, forKey: .engineOrder) ?? d.engineOrder
    }

    /// 所有引擎 ID，按用户排序；新增的引擎追加在末尾，已删除的丢弃。
    public var orderedEngineIDs: [String] {
        let known = [EngineID.dictionary, EngineID.system] + llmEngines.map(\.engineID)
        var result = engineOrder.filter { known.contains($0) }
        for id in known where !result.contains(id) { result.append(id) }
        return result
    }
}

// MARK: - 结果与错误

public nonisolated struct TranslationOutput: Sendable, Equatable {
    public var text: String
    /// 完整的词条（词典引擎）等补充信息。
    public var detail: String?
    public init(text: String, detail: String? = nil) {
        self.text = text
        self.detail = detail
    }
}

public nonisolated struct TranslationResult: Sendable, Equatable {
    public var text: String
    public var detail: String?
    public var engineName: String
    public var from: String
    public var to: String
}

public nonisolated enum TranslateError: Error, LocalizedError, Equatable {
    case unavailable(String)
    case missingKey
    case invalidURL
    case noModel
    case http(Int, String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable(let s): s
        case .missingKey: "未填写 API Key"
        case .invalidURL: "Base URL 无效"
        case .noModel: "未填写模型名"
        case .http(let code, let msg): msg.isEmpty ? "请求失败（HTTP \(code)）" : "请求失败（HTTP \(code)）：\(msg)"
        case .badResponse: "无法解析返回内容"
        }
    }
}

public nonisolated protocol TranslationEngine: Sendable {
    var id: String { get }
    var name: String { get }
    /// 返回 nil 表示这个引擎对该文字没有结果（比如词典里查不到）；抛错表示引擎不可用或请求失败。
    func translate(_ text: String, from: String, to: String) async throws -> TranslationOutput?
}
