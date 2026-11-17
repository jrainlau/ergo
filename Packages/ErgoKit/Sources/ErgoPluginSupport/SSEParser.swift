import Foundation

public struct SSEEvent: Sendable, Equatable {
    public var event: String?
    public var data: String
    public init(event: String?, data: String) {
        self.event = event
        self.data = data
    }
}

/// 逐行 SSE 解析。注意 `URLSession.AsyncBytes.lines` 会丢弃空行，
/// 因此这里在收到每条 `data:` 行时直接产出事件（OpenAI / Anthropic 都是单行 data）。
public struct SSEParser: Sendable {
    private var pendingEvent: String?

    public init() {}

    public mutating func feed(line: String) -> SSEEvent? {
        if line.isEmpty {
            pendingEvent = nil
            return nil
        }
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            pendingEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return nil
        }
        if line.hasPrefix("data:") {
            var d = String(line.dropFirst(5))
            if d.hasPrefix(" ") { d.removeFirst() }
            let ev = SSEEvent(event: pendingEvent, data: d)
            pendingEvent = nil
            return ev
        }
        return nil
    }
}
