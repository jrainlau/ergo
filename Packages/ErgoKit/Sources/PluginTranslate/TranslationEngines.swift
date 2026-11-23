import Foundation
import Translation

/// macOS 自带的离线翻译（Translation 框架）。需要在系统里下载对应的语言包。
public nonisolated struct SystemTranslationEngine: TranslationEngine {
    public let id = EngineID.system
    public let name = "系统翻译"

    public init() {}

    public func translate(_ text: String, from: String, to: String) async throws -> TranslationOutput? {
        let source = Locale.Language(identifier: from)
        let target = Locale.Language(identifier: to)
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: break
        case .supported:
            throw TranslateError.unavailable("系统翻译的语言包未下载（\(TranslateLanguage.name(of: from)) → \(TranslateLanguage.name(of: to))）")
        default:
            throw TranslateError.unavailable("系统翻译不支持 \(TranslateLanguage.name(of: from)) → \(TranslateLanguage.name(of: to))")
        }
        let session = TranslationSession(installedSource: source, target: target)
        let response = try await session.translate(text)
        return TranslationOutput(text: response.targetText)
    }
}

// MARK: - 大模型

public nonisolated enum LLMTranslator {
    public static func systemPrompt(from: String, to: String, extra: String) -> String {
        var s = """
        You are a professional translator. Translate the user's message from \(TranslateLanguage.name(of: from)) (\(from)) \
        into \(TranslateLanguage.name(of: to)) (\(to)). \
        Output only the translation itself: no explanations, no notes, no quotation marks, no pronunciation. \
        Keep the original line breaks, formatting and proper nouns. If the input is a single word, give its most common meanings separated by "; ".
        """
        let e = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.isEmpty { s += "\n" + e }
        return s
    }

    public static func endpoint(_ base: String, path: String) throws -> URL {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        guard !b.isEmpty, let url = URL(string: b + path), url.scheme != nil, url.host != nil else { throw TranslateError.invalidURL }
        return url
    }

    public static func buildRequest(_ config: LLMEngineConfig, apiKey: String?, text: String, from: String, to: String) throws -> URLRequest {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw TranslateError.noModel }
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if config.requiresKey, key.isEmpty { throw TranslateError.missingKey }
        let system = systemPrompt(from: from, to: to, extra: config.extraPrompt)
        switch config.kind {
        case .openAICompatible:
            var req = URLRequest(url: try endpoint(config.baseURL, path: "/chat/completions"), timeoutInterval: 30)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            let body: [String: Any] = [
                "model": model, "temperature": 0.2, "stream": false,
                "messages": [["role": "system", "content": system], ["role": "user", "content": text]],
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req
        case .anthropic:
            var req = URLRequest(url: try endpoint(config.baseURL, path: "/messages"), timeoutInterval: 30)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if !key.isEmpty { req.setValue(key, forHTTPHeaderField: "x-api-key") }
            let body: [String: Any] = [
                "model": model, "max_tokens": 2048, "temperature": 0.2, "system": system,
                "messages": [["role": "user", "content": text]],
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req
        }
    }

    public static func errorMessage(from data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        }
        if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
        if let e = obj["error"] as? String { return e }
        if let m = obj["message"] as? String { return m }
        return ""
    }

    public static func parseResponse(_ data: Data, kind: LLMKind) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TranslateError.badResponse }
        var text: String?
        switch kind {
        case .openAICompatible:
            let message = ((obj["choices"] as? [[String: Any]])?.first)?["message"] as? [String: Any]
            text = message?["content"] as? String
        case .anthropic:
            let blocks = (obj["content"] as? [[String: Any]]) ?? []
            let joined = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
            text = joined.isEmpty ? nil : joined
        }
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { throw TranslateError.badResponse }
        return stripThinking(t)
    }

    /// 部分模型会带上 <think>…</think>。
    static func stripThinking(_ s: String) -> String {
        s.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 发送请求并返回译文。`transport` 便于测试替换。
    public static func translate(
        _ config: LLMEngineConfig, apiKey: String?, text: String, from: String, to: String,
        transport: @Sendable (URLRequest) async throws -> (Data, Int) = { req in
            let (data, resp) = try await URLSession.shared.data(for: req)
            return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
    ) async throws -> String {
        let req = try buildRequest(config, apiKey: apiKey, text: text, from: from, to: to)
        let (data, status) = try await transport(req)
        guard (200..<300).contains(status) else { throw TranslateError.http(status, errorMessage(from: data)) }
        return try parseResponse(data, kind: config.kind)
    }
}

/// 调用大模型翻译。API Key 在创建时从钥匙串读出，引擎本身不碰钥匙串。
public nonisolated struct LLMEngine: TranslationEngine {
    public let config: LLMEngineConfig
    public let apiKey: String?
    public var id: String { config.engineID }
    public var name: String { config.name }

    public init(config: LLMEngineConfig, apiKey: String?) {
        self.config = config
        self.apiKey = apiKey
    }

    public func translate(_ text: String, from: String, to: String) async throws -> TranslationOutput? {
        let out = try await LLMTranslator.translate(config, apiKey: apiKey, text: text, from: from, to: to)
        return TranslationOutput(text: out)
    }
}
