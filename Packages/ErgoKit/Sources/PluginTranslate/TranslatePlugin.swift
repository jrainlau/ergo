import SwiftUI
import ErgoPluginKit

public final class TranslatePlugin: ErgoPlugin {
    public static var manifest: PluginManifest {
        PluginManifest(
            id: "ergo.translate", name: "翻译",
            summary: "输入文字自动中英互译，回车复制译文；没有其他结果时排第一。也可以输入 translate 加空格再输入要翻译的内容",
            symbolName: "character.bubble",
            keywords: [KeywordTrigger(text: "translate")]
        )
    }

    private var context: (any PluginContext)?
    private var settings: SettingsBox<TranslateSettings>?
    private var service: TranslationService?
    private var provider: TranslateProvider?

    public required init() {}

    public func activate(context: any PluginContext) async throws {
        self.context = context
        let box = SettingsBox(store: context.settings, key: "main", default: TranslateSettings())
        settings = box
        let service = TranslationService(context: context, settings: box)
        self.service = service
        provider = TranslateProvider(context: context, settings: box, service: service)
    }

    public func deactivate() async {
        provider = nil
        service = nil
        settings = nil
        context = nil
    }

    public var searchProvider: (any SearchProvider)? { provider }

    public func makeScope() -> (any PluginScope)? {
        guard let context, let service, let settings else { return nil }
        return TranslateScope(context: context, settings: settings, service: service)
    }

    public func makeSettingsView() -> AnyView? {
        guard let settings, let context else { return nil }
        return AnyView(TranslateSettingsView(settings: settings, context: context))
    }
}

// MARK: - 结果项

@MainActor
enum TranslateItemFactory {
    /// 在同一层级里要排在文件搜索等兜底结果之前。
    static let leadingScore = 5.0

    static func item(for r: TranslationResult, context: any PluginContext, score: Double = leadingScore) -> ResultItem {
        let ctx = context
        let text = r.text
        var actions = [
            ResultAction(id: "copy", title: "复制译文") {
                ctx.pasteboard.copy(.text(text), marker: nil)
                ctx.hud.show("已复制译文", symbol: "checkmark.circle")
                return .hideLauncher
            },
            ResultAction(id: "paste", title: "粘贴到前台应用", shortcut: KeyStroke(key: .enter, modifiers: .command)) {
                _ = await ctx.pasteboard.paste(.text(text), marker: nil, restoreClipboard: true)
                return .hideLauncher
            },
            ResultAction(id: "replace", title: "用译文替换输入", shortcut: KeyStroke(key: .enter, modifiers: .option)) {
                .setQuery(text)
            },
        ]
        if let detail = r.detail {
            actions.append(ResultAction(id: "copyEntry", title: "复制完整词条", shortcut: KeyStroke(key: .character("c"), modifiers: [.command, .shift])) {
                ctx.pasteboard.copy(.text(detail), marker: nil)
                ctx.hud.show("已复制词条", symbol: "checkmark.circle")
                return .hideLauncher
            })
        }
        return ResultItem(
            id: "tr:\(r.to)",
            title: text.replacingOccurrences(of: "\n", with: " "),
            subtitle: "\(TranslateLanguage.name(of: r.from)) → \(TranslateLanguage.name(of: r.to)) · \(r.engineName)",
            icon: .symbol("character.bubble"),
            score: score,
            actions: actions
        )
    }

    /// 关键词作用域里没有结果时，告诉用户为什么。
    static func messageItem(for outcome: TranslationOutcome, hasEngines: Bool, context: any PluginContext) -> ResultItem {
        let title: String
        if outcome.detected == nil {
            title = "无法判断语言，或该语言不在已配置的语言对里"
        } else if !hasEngines {
            title = "没有启用的翻译引擎"
        } else if let e = outcome.errors.first {
            title = e
        } else {
            title = "没有找到译文"
        }
        let ctx = context
        return ResultItem(
            id: "tr.message", title: title,
            subtitle: outcome.errors.count > 1 ? "另有 \(outcome.errors.count - 1) 个引擎失败，可在设置里查看和调整" : "回车打开翻译设置",
            icon: .symbol("exclamationmark.triangle"),
            actions: [
                ResultAction(id: "settings", title: "打开翻译设置") {
                    ctx.launcher.openSettings(for: TranslatePlugin.manifest.id, openManagement: false)
                    return .hideLauncher
                },
            ]
        )
    }
}

// MARK: - 主搜索框

@MainActor
final class TranslateProvider: SearchProvider {
    let participation: SearchParticipation = .trailing
    let tier: ResultTier = .fallback

    private let context: any PluginContext
    private let settings: SettingsBox<TranslateSettings>
    private let service: TranslationService

    init(context: any PluginContext, settings: SettingsBox<TranslateSettings>, service: TranslationService) {
        self.context = context
        self.settings = settings
        self.service = service
    }

    func canHandle(_ query: SearchQuery) -> Bool {
        let s = settings.value
        return s.autoInSearch && TranslateHeuristics.isTranslatable(query.text, maxChars: s.searchMaxChars)
    }

    func search(_ query: SearchQuery) async throws -> SearchOutput {
        // 去抖：连续输入时上一次会被取消，避免白白发请求
        try await Task.sleep(for: .milliseconds(300))
        let outcome = await service.translate(query.text, mode: .search)
        try Task.checkCancellation()
        guard let r = outcome.results.first else { return .none }
        return .items([TranslateItemFactory.item(for: r, context: context)])
    }
}

// MARK: - translate 关键词

@MainActor
final class TranslateScope: PluginScope {
    let title = "翻译"
    let placeholder = "输入要翻译的文字，自动判断语言"
    let style: ScopeStyle = .list

    private let context: any PluginContext
    private let settings: SettingsBox<TranslateSettings>
    private let service: TranslationService

    init(context: any PluginContext, settings: SettingsBox<TranslateSettings>, service: TranslationService) {
        self.context = context
        self.settings = settings
        self.service = service
    }

    func items(for query: SearchQuery) async throws -> [ResultItem] {
        guard !query.text.isEmpty else { return [] }
        try await Task.sleep(for: .milliseconds(250))
        let outcome = await service.translate(query.text, mode: .scope)
        try Task.checkCancellation()
        if outcome.results.isEmpty {
            return [TranslateItemFactory.messageItem(for: outcome, hasEngines: !service.engines(for: .scope).isEmpty, context: context)]
        }
        return outcome.results.map { TranslateItemFactory.item(for: $0, context: context, score: 1) }
    }
}
