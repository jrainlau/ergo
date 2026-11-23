import SwiftUI

public struct SearchQuery: Sendable {
    public let sequence: UInt64
    public let raw: String
    public let text: String
    public let normalized: String

    public init(sequence: UInt64, raw: String) {
        self.sequence = sequence
        self.raw = raw
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = trimmed
        self.normalized = SearchQuery.normalize(trimmed)
    }

    /// 小写 + 折叠变音 + 全半角统一
    public static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

public enum SearchParticipation: Sendable {
    case global
    case fallback(maxItems: Int, minQueryLength: Int)
    /// 总是参与，但不算作“命中”：不会阻止 `.fallback` 的 provider 运行。
    /// 结果按 `tier` 与其他结果一起排序（翻译插件用 `.fallback` 层级：有应用等强命中时排在它们后面，没有时排第一）。
    /// 因为可能做网络请求，搜索的超时放宽到 20 秒。
    case trailing
    case none
}

public enum ResultTier: Int, Sendable, Comparable {
    case instant = 0, primary = 1, secondary = 2, fallback = 3
    public static func < (lhs: ResultTier, rhs: ResultTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

@MainActor
public struct InlinePanel {
    public var id: String
    public var height: CGFloat
    public var exclusive: Bool
    public var view: AnyView
    public var handleKey: (KeyStroke) -> Bool

    public init(id: String, height: CGFloat, exclusive: Bool = true, view: AnyView, handleKey: @escaping (KeyStroke) -> Bool = { _ in false }) {
        self.id = id
        self.height = height
        self.exclusive = exclusive
        self.view = view
        self.handleKey = handleKey
    }
}

@MainActor
public enum SearchOutput {
    case items([ResultItem])
    case panel(InlinePanel)
    case none
}

@MainActor
public protocol SearchProvider: AnyObject {
    var participation: SearchParticipation { get }
    var tier: ResultTier { get }
    /// 必须同步、< 1ms
    func canHandle(_ query: SearchQuery) -> Bool
    func search(_ query: SearchQuery) async throws -> SearchOutput
}
