import SwiftUI
import ErgoPluginKit
import ErgoPluginSupport
import ErgoUI

public nonisolated struct CalculatorSettings: Codable, Equatable, Sendable {
    public var useDegrees = false
    public var maxSignificantDigits = 15
    public init() {}
}

public final class CalculatorPlugin: ErgoPlugin {
    public static var manifest: PluginManifest {
        PluginManifest(
            id: "ergo.calculator", name: "计算器",
            summary: "直接输入算式，例如 1+1、sqrt(16)、2pi",
            symbolName: "plusminus.circle"
        )
    }

    private var provider: CalculatorProvider?
    private var settings: SettingsBox<CalculatorSettings>?

    public required init() {}

    public func activate(context: any PluginContext) async throws {
        let box = SettingsBox(store: context.settings, key: "main", default: CalculatorSettings())
        settings = box
        provider = CalculatorProvider(context: context, settings: box)
    }

    public func deactivate() async {
        provider = nil
        settings = nil
    }

    public var searchProvider: (any SearchProvider)? { provider }

    public func makeSettingsView() -> AnyView? {
        guard let settings else { return nil }
        return AnyView(CalculatorSettingsView(settings: settings))
    }
}

struct CalculatorSettingsView: View {
    @Bindable var settings: SettingsBox<CalculatorSettings>

    var body: some View {
        Section("计算") {
            Toggle("三角函数使用角度（默认弧度）", isOn: $settings.value.useDegrees)
            Stepper("最多显示 \(settings.value.maxSignificantDigits) 位有效数字", value: $settings.value.maxSignificantDigits, in: 6...15)
        }
    }
}

@MainActor
final class CalculatorProvider: SearchProvider {
    let participation: SearchParticipation = .global
    let tier: ResultTier = .instant

    private let context: any PluginContext
    private let settings: SettingsBox<CalculatorSettings>

    init(context: any PluginContext, settings: SettingsBox<CalculatorSettings>) {
        self.context = context
        self.settings = settings
    }

    nonisolated static func looksLikeExpression(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("=") || trimmed.hasPrefix("＝") { return trimmed.count > 1 }
        let n = MathExpression.normalize(text)
        guard !n.isEmpty else { return false }
        let allowed = Set("0123456789abcdefghijklmnopqrstuvwxyz.+-*/%^()!,")
        guard n.allSatisfy({ allowed.contains($0) }) else { return false }
        guard n.contains(where: { $0.isASCII && $0.isNumber }) else { return false }
        let operators = Set("+-*/%^!(")
        let chars = Array(n)
        let hasOperator = chars.enumerated().contains { $0.offset > 0 && operators.contains($0.element) }
        return hasOperator
    }

    func canHandle(_ query: SearchQuery) -> Bool {
        Self.looksLikeExpression(query.raw)
    }

    func search(_ query: SearchQuery) async throws -> SearchOutput {
        let value: Double
        do {
            value = try MathExpression.evaluate(query.raw, degrees: settings.value.useDegrees)
        } catch {
            return .none
        }
        let digits = settings.value.maxSignificantDigits
        let raw = MathExpression.rawString(value)
        let shown = MathExpression.formatted(value, maxSignificantDigits: digits)
        let expr = query.text.hasPrefix("=") ? String(query.text.dropFirst()).trimmingCharacters(in: .whitespaces) : query.text

        var items = [makeItem(id: "result", title: "= \(shown)", subtitle: expr, raw: raw, score: 1.0)]
        if value == value.rounded(), value >= 0, value < 9_007_199_254_740_992 {
            let i = UInt64(value)
            if i > 1 {
                items.append(makeItem(id: "hex", title: "0x" + String(i, radix: 16, uppercase: true), subtitle: "十六进制", raw: "0x" + String(i, radix: 16, uppercase: true), score: 0.9))
                items.append(makeItem(id: "bin", title: "0b" + String(i, radix: 2), subtitle: "二进制", raw: "0b" + String(i, radix: 2), score: 0.89))
            }
        }
        return .items(items)
    }

    private func makeItem(id: String, title: String, subtitle: String, raw: String, score: Double) -> ResultItem {
        let ctx = context
        return ResultItem(
            id: id, title: title, subtitle: subtitle,
            icon: .symbol("equal.square"), score: score,
            actions: [
                ResultAction(id: "copy", title: "复制结果") {
                    ctx.pasteboard.copy(.text(raw), marker: nil)
                    ctx.hud.show("已复制", symbol: "checkmark.circle")
                    return .hideLauncher
                },
                ResultAction(id: "paste", title: "粘贴到前台应用", shortcut: KeyStroke(key: .enter, modifiers: .command)) {
                    _ = await ctx.pasteboard.paste(.text(raw), marker: nil, restoreClipboard: true)
                    return .hideLauncher
                },
                ResultAction(id: "replace", title: "用结果替换输入", shortcut: KeyStroke(key: .enter, modifiers: .option)) {
                    .setQuery(raw)
                },
            ]
        )
    }
}
