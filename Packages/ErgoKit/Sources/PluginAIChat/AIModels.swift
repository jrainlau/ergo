import Foundation

public nonisolated enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case openAICompatible, anthropic
    public var title: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容"
        case .anthropic: "Anthropic"
        }
    }
}

public nonisolated struct AIProviderConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: AIProviderKind
    public var baseURL: String
    public var models: [String]
    public var defaultModel: String
    public var extraHeaders: [String: String]
    public var requiresKey: Bool

    public init(id: String = UUID().uuidString, name: String, kind: AIProviderKind, baseURL: String, models: [String] = [], defaultModel: String = "", extraHeaders: [String: String] = [:], requiresKey: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.models = models
        self.defaultModel = defaultModel
        self.extraHeaders = extraHeaders
        self.requiresKey = requiresKey
    }

    public var keyAccount: String { "ai.\(id)" }
}

public nonisolated struct AIPreset: Sendable {
    public var name: String
    public var kind: AIProviderKind
    public var baseURL: String
    public var requiresKey = true

    public static let all: [AIPreset] = [
        AIPreset(name: "OpenAI", kind: .openAICompatible, baseURL: "https://api.openai.com/v1"),
        AIPreset(name: "Anthropic", kind: .anthropic, baseURL: "https://api.anthropic.com/v1"),
        AIPreset(name: "Google Gemini（OpenAI 兼容）", kind: .openAICompatible, baseURL: "https://generativelanguage.googleapis.com/v1beta/openai"),
        AIPreset(name: "DeepSeek", kind: .openAICompatible, baseURL: "https://api.deepseek.com/v1"),
        AIPreset(name: "Moonshot", kind: .openAICompatible, baseURL: "https://api.moonshot.cn/v1"),
        AIPreset(name: "通义千问", kind: .openAICompatible, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1"),
        AIPreset(name: "智谱", kind: .openAICompatible, baseURL: "https://open.bigmodel.cn/api/paas/v4"),
        AIPreset(name: "OpenRouter", kind: .openAICompatible, baseURL: "https://openrouter.ai/api/v1"),
        AIPreset(name: "SiliconFlow", kind: .openAICompatible, baseURL: "https://api.siliconflow.cn/v1"),
        AIPreset(name: "Ollama（本地）", kind: .openAICompatible, baseURL: "http://localhost:11434/v1", requiresKey: false),
        AIPreset(name: "自定义", kind: .openAICompatible, baseURL: ""),
    ]
}

public nonisolated struct AIChatSettings: Codable, Equatable, Sendable {
    public var providers: [AIProviderConfig] = []
    public var defaultProviderID: String?
    public var systemPrompt = "你是一个简洁、准确的助手，默认使用简体中文回答。"
    public var temperature = 0.7
    public var contextMessages = 20
    public var contextMaxChars = 24_000
    public var resumeMinutes = 30
    public init() {}
}

// MARK: - 请求 / 响应

public nonisolated struct ChatTurn: Sendable, Equatable {
    public var role: String   // user / assistant
    public var content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public nonisolated struct ChatRequest: Sendable {
    public var kind: AIProviderKind
    public var baseURL: String
    public var apiKey: String?
    public var extraHeaders: [String: String]
    public var model: String
    public var system: String?
    public var messages: [ChatTurn]
    public var temperature: Double
    public init(kind: AIProviderKind, baseURL: String, apiKey: String?, extraHeaders: [String: String] = [:], model: String, system: String?, messages: [ChatTurn], temperature: Double = 0.7) {
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.extraHeaders = extraHeaders
        self.model = model
        self.system = system
        self.messages = messages
        self.temperature = temperature
    }
}

public nonisolated enum ChatDelta: Sendable, Equatable {
    case text(String)
    case reasoning(String)
}

public nonisolated enum ChatError: Error, LocalizedError, Equatable {
    case http(Int, String)
    case api(String)
    case invalidURL
    case noModel

    public var errorDescription: String? {
        switch self {
        case .http(let code, let msg): msg.isEmpty ? "请求失败（HTTP \(code)）" : "请求失败（HTTP \(code)）：\(msg)"
        case .api(let msg): msg
        case .invalidURL: "Base URL 无效"
        case .noModel: "未选择模型"
        }
    }
}

public nonisolated enum ContextBuilder {
    /// 取最近 maxMessages 条，且总字符数不超过 maxChars（从最早的开始丢）；保证以 user 开头。
    public static func build(_ all: [ChatTurn], maxMessages: Int, maxChars: Int) -> [ChatTurn] {
        var msgs = Array(all.suffix(max(1, maxMessages)))
        var total = msgs.reduce(0) { $0 + $1.content.count }
        while msgs.count > 1, total > maxChars {
            total -= msgs.removeFirst().content.count
        }
        while let f = msgs.first, f.role != "user", msgs.count > 1 { msgs.removeFirst() }
        return msgs
    }
}
