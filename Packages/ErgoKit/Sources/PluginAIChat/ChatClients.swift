import Foundation
import ErgoPluginSupport

// MARK: - 传输层（可替换，便于测试）

public nonisolated protocol ChatTransport: Sendable {
    func open(_ request: URLRequest) async throws -> (status: Int, lines: AsyncThrowingStream<String, Error>)
}

public nonisolated struct URLSessionTransport: ChatTransport {
    public init() {}

    public func open(_ request: URLRequest) async throws -> (status: Int, lines: AsyncThrowingStream<String, Error>) {
        let (bytes, resp) = try await URLSession.shared.bytes(for: request)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let stream = AsyncThrowingStream<String, Error> { cont in
            let task = Task {
                do {
                    for try await line in bytes.lines { cont.yield(line) }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
        return (status, stream)
    }
}

// MARK: - 请求构建

public nonisolated enum ChatRequestBuilder {
    public static func endpoint(_ base: String, path: String) throws -> URL {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        guard !b.isEmpty, let url = URL(string: b + path), url.scheme != nil, url.host != nil else { throw ChatError.invalidURL }
        return url
    }

    public static func build(_ r: ChatRequest) throws -> URLRequest {
        guard !r.model.isEmpty else { throw ChatError.noModel }
        switch r.kind {
        case .openAICompatible:
            var req = URLRequest(url: try endpoint(r.baseURL, path: "/chat/completions"), timeoutInterval: 120)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            if let k = r.apiKey, !k.isEmpty { req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
            var msgs: [[String: String]] = []
            if let s = r.system, !s.isEmpty { msgs.append(["role": "system", "content": s]) }
            msgs += r.messages.map { ["role": $0.role, "content": $0.content] }
            let body: [String: Any] = ["model": r.model, "messages": msgs, "stream": true, "temperature": r.temperature]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            for (k, v) in r.extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
            return req
        case .anthropic:
            var req = URLRequest(url: try endpoint(r.baseURL, path: "/messages"), timeoutInterval: 120)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if let k = r.apiKey, !k.isEmpty { req.setValue(k, forHTTPHeaderField: "x-api-key") }
            var body: [String: Any] = [
                "model": r.model, "max_tokens": 4096, "stream": true,
                "messages": r.messages.map { ["role": $0.role, "content": $0.content] },
                "temperature": min(1, r.temperature),
            ]
            if let s = r.system, !s.isEmpty { body["system"] = s }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            for (k, v) in r.extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
            return req
        }
    }

    public static func modelsRequest(kind: AIProviderKind, baseURL: String, apiKey: String?, extraHeaders: [String: String]) throws -> URLRequest {
        var req = URLRequest(url: try endpoint(baseURL, path: "/models"), timeoutInterval: 20)
        switch kind {
        case .openAICompatible:
            if let k = apiKey, !k.isEmpty { req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        case .anthropic:
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if let k = apiKey, !k.isEmpty { req.setValue(k, forHTTPHeaderField: "x-api-key") }
        }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }

    public static func parseModelList(_ data: Data) -> [String] {
        struct R: Decodable { struct M: Decodable { var id: String }; var data: [M]? }
        let ids = (try? JSONDecoder().decode(R.self, from: data))?.data?.map(\.id) ?? []
        return ids.sorted()
    }
}

// MARK: - 流式解析

public nonisolated enum ChatStreamParser {
    /// 从 JSON 的 error 字段里取消息。
    public static func errorMessage(from json: Any?) -> String? {
        guard let obj = json as? [String: Any] else { return nil }
        if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
        if let e = obj["error"] as? String { return e }
        if let m = obj["message"] as? String { return m }
        return nil
    }

    /// OpenAI 兼容：返回 nil 表示该事件没有增量。
    public static func openAIDelta(_ data: String) throws -> ChatDelta? {
        guard let d = data.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if obj["error"] != nil, let m = errorMessage(from: obj) { throw ChatError.api(m) }
        guard let choice = (obj["choices"] as? [[String: Any]])?.first, let delta = choice["delta"] as? [String: Any] else { return nil }
        if let t = delta["content"] as? String, !t.isEmpty { return .text(t) }
        if let r = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String), !r.isEmpty { return .reasoning(r) }
        return nil
    }

    public enum AnthropicOutcome: Equatable { case delta(ChatDelta), stop, none }

    public static func anthropicEvent(event: String?, data: String) throws -> AnthropicOutcome {
        guard let d = data.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return .none }
        let type = (obj["type"] as? String) ?? event ?? ""
        switch type {
        case "content_block_delta":
            guard let delta = obj["delta"] as? [String: Any], let dt = delta["type"] as? String else { return .none }
            if dt == "text_delta", let t = delta["text"] as? String, !t.isEmpty { return .delta(.text(t)) }
            if dt == "thinking_delta", let t = delta["thinking"] as? String, !t.isEmpty { return .delta(.reasoning(t)) }
            return .none
        case "message_stop": return .stop
        case "error": throw ChatError.api(errorMessage(from: obj) ?? "未知错误")
        default: return .none
        }
    }
}

// MARK: - 客户端

public nonisolated protocol ChatClient: Sendable {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatDelta, Error>
}

public nonisolated struct StreamingChatClient: ChatClient {
    public var transport: any ChatTransport
    public init(transport: any ChatTransport = URLSessionTransport()) { self.transport = transport }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatDelta, Error> {
        let transport = self.transport
        return AsyncThrowingStream { cont in
            let task = Task {
                do {
                    let urlReq = try ChatRequestBuilder.build(request)
                    let (status, lines) = try await transport.open(urlReq)
                    guard (200..<300).contains(status) else {
                        var body = ""
                        for try await l in lines { body += l + "\n" }
                        let msg = ChatStreamParser.errorMessage(from: try? JSONSerialization.jsonObject(with: Data(body.utf8))) ?? String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
                        throw ChatError.http(status, msg)
                    }
                    var parser = SSEParser()
                    loop: for try await line in lines {
                        try Task.checkCancellation()
                        guard let ev = parser.feed(line: line) else { continue }
                        switch request.kind {
                        case .openAICompatible:
                            if ev.data == "[DONE]" { break loop }
                            if let d = try ChatStreamParser.openAIDelta(ev.data) { cont.yield(d) }
                        case .anthropic:
                            switch try ChatStreamParser.anthropicEvent(event: ev.event, data: ev.data) {
                            case .delta(let d): cont.yield(d)
                            case .stop: break loop
                            case .none: break
                            }
                        }
                    }
                    cont.finish()
                } catch is CancellationError {
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}

public nonisolated enum ModelLister {
    public static func fetch(kind: AIProviderKind, baseURL: String, apiKey: String?, extraHeaders: [String: String]) async throws -> [String] {
        let req = try ChatRequestBuilder.modelsRequest(kind: kind, baseURL: baseURL, apiKey: apiKey, extraHeaders: extraHeaders)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = ChatStreamParser.errorMessage(from: try? JSONSerialization.jsonObject(with: data)) ?? ""
            throw ChatError.http(status, msg)
        }
        return ChatRequestBuilder.parseModelList(data)
    }
}
