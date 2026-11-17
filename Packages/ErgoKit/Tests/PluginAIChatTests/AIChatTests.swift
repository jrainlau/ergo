import Foundation
import Testing
import ErgoPluginSupport
@testable import PluginAIChat

// MARK: - SSE 解析

@Suite struct SSEParserTests {
    @Test func dataAndEventLines() {
        var p = SSEParser()
        #expect(p.feed(line: "event: content_block_delta") == nil)
        let e = p.feed(line: #"data: {"a":1}"#)
        #expect(e == SSEEvent(event: "content_block_delta", data: #"{"a":1}"#))
        #expect(p.feed(line: "data: [DONE]") == SSEEvent(event: nil, data: "[DONE]"))
    }

    @Test func commentsAndBlankIgnored() {
        var p = SSEParser()
        #expect(p.feed(line: ": keep-alive") == nil)
        #expect(p.feed(line: "") == nil)
        #expect(p.feed(line: "data:x") == SSEEvent(event: nil, data: "x"))
    }

    @Test func eventResetByBlankLine() {
        var p = SSEParser()
        _ = p.feed(line: "event: a")
        _ = p.feed(line: "")
        #expect(p.feed(line: "data: y")?.event == nil)
    }
}

// MARK: - 解析与请求构建

@Suite struct ParserTests {
    @Test func openAIDeltas() throws {
        #expect(try ChatStreamParser.openAIDelta(#"{"choices":[{"delta":{"content":"你好"}}]}"#) == .text("你好"))
        #expect(try ChatStreamParser.openAIDelta(#"{"choices":[{"delta":{"reasoning_content":"想"}}]}"#) == .reasoning("想"))
        #expect(try ChatStreamParser.openAIDelta(#"{"choices":[{"delta":{"role":"assistant"}}]}"#) == nil)
        #expect(try ChatStreamParser.openAIDelta(#"{"choices":[]}"#) == nil)
        #expect(try ChatStreamParser.openAIDelta("not json") == nil)
        #expect(throws: ChatError.api("bad key")) { try ChatStreamParser.openAIDelta(#"{"error":{"message":"bad key"}}"#) }
    }

    @Test func anthropicEvents() throws {
        #expect(try ChatStreamParser.anthropicEvent(event: "content_block_delta", data: #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}"#) == .delta(.text("Hi")))
        #expect(try ChatStreamParser.anthropicEvent(event: nil, data: #"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hm"}}"#) == .delta(.reasoning("hm")))
        #expect(try ChatStreamParser.anthropicEvent(event: nil, data: #"{"type":"message_stop"}"#) == .stop)
        #expect(try ChatStreamParser.anthropicEvent(event: nil, data: #"{"type":"ping"}"#) == .none)
        #expect(throws: ChatError.api("overloaded")) { try ChatStreamParser.anthropicEvent(event: "error", data: #"{"type":"error","error":{"type":"overloaded_error","message":"overloaded"}}"#) }
    }

    @Test func openAIRequestShape() throws {
        let r = ChatRequest(kind: .openAICompatible, baseURL: "https://api.example.com/v1/", apiKey: "sk-1", extraHeaders: ["X-Test": "1"], model: "m", system: "sys", messages: [ChatTurn(role: "user", content: "hi")], temperature: 0.3)
        let u = try ChatRequestBuilder.build(r)
        #expect(u.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(u.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        #expect(u.value(forHTTPHeaderField: "X-Test") == "1")
        let body = try JSONSerialization.jsonObject(with: u.httpBody!) as! [String: Any]
        #expect(body["stream"] as? Bool == true)
        #expect(body["model"] as? String == "m")
        let msgs = body["messages"] as! [[String: String]]
        #expect(msgs.first == ["role": "system", "content": "sys"])
        #expect(msgs.last == ["role": "user", "content": "hi"])
    }

    @Test func anthropicRequestShape() throws {
        let r = ChatRequest(kind: .anthropic, baseURL: "https://api.anthropic.com/v1", apiKey: "k", model: "claude", system: "sys", messages: [ChatTurn(role: "user", content: "hi")])
        let u = try ChatRequestBuilder.build(r)
        #expect(u.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(u.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(u.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(u.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: u.httpBody!) as! [String: Any]
        #expect(body["system"] as? String == "sys")
        #expect(body["max_tokens"] as? Int == 4096)
        #expect((body["messages"] as! [[String: String]]).count == 1)
    }

    @Test func invalidInputs() {
        #expect(throws: ChatError.invalidURL) { try ChatRequestBuilder.endpoint("", path: "/x") }
        #expect(throws: ChatError.invalidURL) { try ChatRequestBuilder.endpoint("not a url", path: "/x") }
        let r = ChatRequest(kind: .openAICompatible, baseURL: "https://a.b", apiKey: nil, model: "", system: nil, messages: [])
        #expect(throws: ChatError.noModel) { try ChatRequestBuilder.build(r) }
    }

    @Test func modelListParsing() {
        let json = #"{"data":[{"id":"b"},{"id":"a"}]}"#
        #expect(ChatRequestBuilder.parseModelList(Data(json.utf8)) == ["a", "b"])
        #expect(ChatRequestBuilder.parseModelList(Data("x".utf8)).isEmpty)
    }
}

// MARK: - 流式客户端（模拟传输）

private struct MockTransport: ChatTransport {
    var status: Int
    var lines: [String]
    func open(_ request: URLRequest) async throws -> (status: Int, lines: AsyncThrowingStream<String, Error>) {
        let ls = lines
        return (status, AsyncThrowingStream { c in for l in ls { c.yield(l) }; c.finish() })
    }
}

private func collect(_ s: AsyncThrowingStream<ChatDelta, Error>) async throws -> [ChatDelta] {
    var out: [ChatDelta] = []
    for try await d in s { out.append(d) }
    return out
}

@Suite struct ClientTests {
    private func req(_ kind: AIProviderKind) -> ChatRequest {
        ChatRequest(kind: kind, baseURL: "https://x.test/v1", apiKey: "k", model: "m", system: nil, messages: [ChatTurn(role: "user", content: "hi")])
    }

    @Test func openAIStream() async throws {
        let lines = [
            #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
            #"data: {"choices":[{"delta":{"reasoning_content":"think"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"lo"}}]}"#,
            "data: [DONE]",
            #"data: {"choices":[{"delta":{"content":"IGNORED"}}]}"#,
        ]
        let c = StreamingChatClient(transport: MockTransport(status: 200, lines: lines))
        #expect(try await collect(c.stream(req(.openAICompatible))) == [.reasoning("think"), .text("Hel"), .text("lo")])
    }

    @Test func anthropicStream() async throws {
        let lines = [
            "event: message_start", #"data: {"type":"message_start"}"#,
            "event: content_block_delta", #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"A"}}"#,
            "event: content_block_delta", #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"B"}}"#,
            "event: message_stop", #"data: {"type":"message_stop"}"#,
            "event: content_block_delta", #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"IGNORED"}}"#,
        ]
        let c = StreamingChatClient(transport: MockTransport(status: 200, lines: lines))
        #expect(try await collect(c.stream(req(.anthropic))) == [.text("A"), .text("B")])
    }

    @Test func anthropicErrorEvent() async {
        let lines = ["event: error", #"data: {"type":"error","error":{"message":"boom"}}"#]
        let c = StreamingChatClient(transport: MockTransport(status: 200, lines: lines))
        await #expect(throws: ChatError.api("boom")) { try await collect(c.stream(req(.anthropic))) }
    }

    @Test func httpErrorExtractsMessage() async {
        let c = StreamingChatClient(transport: MockTransport(status: 401, lines: [#"{"error":{"message":"Invalid API key"}}"#]))
        await #expect(throws: ChatError.http(401, "Invalid API key")) { try await collect(c.stream(req(.openAICompatible))) }
    }

    @Test func httpErrorPlainText() async {
        let c = StreamingChatClient(transport: MockTransport(status: 502, lines: ["Bad Gateway"]))
        await #expect(throws: ChatError.http(502, "Bad Gateway")) { try await collect(c.stream(req(.openAICompatible))) }
    }

    @Test func cancellationFinishesQuietly() async throws {
        struct Slow: ChatTransport {
            func open(_ request: URLRequest) async throws -> (status: Int, lines: AsyncThrowingStream<String, Error>) {
                (200, AsyncThrowingStream { c in
                    let t = Task { for i in 0..<1000 { c.yield(#"data: {"choices":[{"delta":{"content":"x\#(i)"}}]}"#); try? await Task.sleep(for: .milliseconds(5)) }; c.finish() }
                    c.onTermination = { _ in t.cancel() }
                })
            }
        }
        let c = StreamingChatClient(transport: Slow())
        let task = Task { () -> Int in
            var n = 0
            for try await _ in c.stream(req(.openAICompatible)) { n += 1; if n == 3 { break } }
            return n
        }
        #expect(try await task.value == 3)
    }
}

// MARK: - 上下文与存储

@Suite struct ContextTests {
    @Test func limitsCountAndStartsWithUser() {
        let all = (0..<10).map { ChatTurn(role: $0 % 2 == 0 ? "user" : "assistant", content: "m\($0)") }
        let r = ContextBuilder.build(all, maxMessages: 5, maxChars: 10_000)
        #expect(r.count == 4)       // 最近 5 条以 assistant 开头，被丢弃
        #expect(r.first?.role == "user")
        #expect(r.last?.content == "m9")
    }

    @Test func limitsChars() {
        let all = [ChatTurn(role: "user", content: String(repeating: "a", count: 100)),
                   ChatTurn(role: "assistant", content: String(repeating: "b", count: 100)),
                   ChatTurn(role: "user", content: String(repeating: "c", count: 100))]
        let r = ContextBuilder.build(all, maxMessages: 20, maxChars: 150)
        #expect(r.count == 1)
        #expect(r[0].content.first == "c")
    }

    @Test func keepsLastEvenIfHuge() {
        let r = ContextBuilder.build([ChatTurn(role: "user", content: String(repeating: "x", count: 500))], maxMessages: 20, maxChars: 10)
        #expect(r.count == 1)
    }
}

@Suite struct StoreTests {
    @Test func titleTruncation() {
        #expect(ChatStore.title(from: "你好\n第二行") == "你好")
        #expect(ChatStore.title(from: String(repeating: "字", count: 50)).count == 30)
        #expect(ChatStore.title(from: "  ") == "新对话")
    }

    @Test func conversationLifecycle() throws {
        let s = try ChatStore()
        let c = try s.createConversation(title: "t", providerID: "p", model: "m", now: Date(timeIntervalSince1970: 100))
        let u = try s.addMessage(conversationID: c.id, role: "user", content: "hi")
        let a = try s.addMessage(conversationID: c.id, role: "assistant", content: "", status: .streaming)
        try s.update(messageID: a.id, content: "hello", reasoning: "r", status: .done)
        let msgs = try s.messages(in: c.id)
        #expect(msgs.map(\.id) == [u.id, a.id])
        #expect(msgs[1].content == "hello" && msgs[1].reasoning == "r" && msgs[1].messageStatus == .done)

        let c2 = try s.createConversation(title: "newer", providerID: nil, model: nil, now: Date(timeIntervalSince1970: 200))
        #expect(try s.latestConversation()?.id == c2.id)
        try s.touch(c.id, model: nil, providerID: nil, now: Date(timeIntervalSince1970: 300))
        #expect(try s.latestConversation()?.id == c.id)
        #expect(try s.conversation(id: c.id)?.model == "m")

        try s.deleteConversation(id: c.id)
        #expect(try s.messages(in: c.id).isEmpty)
    }

    @Test func settingsCodableDefaults() throws {
        let s = AIChatSettings()
        #expect(s.contextMessages == 20 && s.contextMaxChars == 24_000 && s.resumeMinutes == 30)
        let p = AIProviderConfig(name: "x", kind: .anthropic, baseURL: "u")
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(AIProviderConfig.self, from: data) == p)
        #expect(p.keyAccount == "ai.\(p.id)")
    }
}
