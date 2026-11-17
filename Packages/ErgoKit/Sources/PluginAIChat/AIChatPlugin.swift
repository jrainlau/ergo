import AppKit
import SwiftUI
import ErgoPluginKit
import ErgoUI

public final class AIChatPlugin: ErgoPlugin {
    public static var manifest: PluginManifest {
        PluginManifest(
            id: "ergo.ai", name: "AI 问答",
            summary: "在启动器内与大模型对话，支持 OpenAI 兼容接口与 Anthropic",
            symbolName: "sparkles",
            keywords: [KeywordTrigger(text: "ai")],
            hotkeys: [HotkeyActionDescriptor(id: "ai.open", title: "唤起 AI 问答", defaultTrigger: .none)]
        )
    }

    var context: (any PluginContext)?
    var settings: SettingsBox<AIChatSettings>?
    var store: ChatStore?
    var session: ChatSession?

    public required init() {}

    public func activate(context: any PluginContext) async throws {
        self.context = context
        let box = SettingsBox(store: context.settings, key: "main", default: AIChatSettings())
        settings = box
        let st = try ChatStore(path: context.dataDirectory.appendingPathComponent("ai.sqlite").path)
        store = st
        session = ChatSession(store: st, settings: box, secrets: context.secrets)
    }

    public func deactivate() async {
        session?.stop()
        session = nil
        store = nil
        settings = nil
    }

    public func makeScope() -> (any PluginScope)? {
        guard let session, let context else { return nil }
        return AIChatScope(session: session, context: context)
    }

    public func perform(hotkey: HotkeyActionID) async {
        guard let context else { return }
        if context.launcher.isVisible { context.launcher.hide() } else { context.launcher.show(scope: Self.manifest.id, query: nil) }
    }

    public func makeSettingsView() -> AnyView? {
        guard let settings, let context else { return nil }
        return AnyView(AISettingsView(settings: settings, context: context))
    }
}

@MainActor
final class AIChatScope: PluginScope {
    let title = "AI 问答"
    let placeholder = "向 AI 提问…"
    let style: ScopeStyle = .custom(height: 600, showsHostInput: false)
    private let session: ChatSession
    private let context: any PluginContext

    init(session: ChatSession, context: any PluginContext) {
        self.session = session
        self.context = context
        session.enter()
    }

    func makeCustomView() -> AnyView {
        let ctx = context
        return AnyView(AIChatView(session: session, openSettings: {
            ctx.launcher.openSettings(for: AIChatPlugin.manifest.id, openManagement: false)
        }))
    }

    func handleKey(_ press: KeyStroke) -> Bool {
        if press.key == .escape && press.modifiers.isEmpty {
            if session.showHistory { session.showHistory = false; return true }
            if session.isStreaming { session.stop(); return true }
            return false
        }
        guard press.modifiers == .command, case .character(let c) = press.key else { return false }
        switch c {
        case "n": session.newConversation(); return true
        case "y": session.toggleHistory(); return true
        case "c":
            if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.selectedRange().length > 0 { return false }
            guard let text = session.lastAssistantText else { return false }
            context.pasteboard.copy(.text(text), marker: nil)
            context.hud.show("已复制回答", symbol: "checkmark.circle")
            return true
        default: return false
        }
    }

    func didClose() {}
}
