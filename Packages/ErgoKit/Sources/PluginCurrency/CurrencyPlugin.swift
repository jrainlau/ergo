import AppKit
import Observation
import SwiftUI
import ErgoPluginKit
import ErgoPluginSupport
import ErgoUI

public nonisolated struct CurrencySettings: Codable, Equatable, Sendable {
    public var provider: RateProviderKind = .frankfurter
    public var yenIsJPY = false
    public var favorites: [String] = ["CNY", "USD", "EUR", "JPY", "HKD", "GBP", "KRW", "SGD", "AUD", "CAD"]
    public var refreshMinutes = 60
    public init() {}
}

@MainActor
@Observable
final class RateStore {
    private(set) var table: RateTable?
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private var kind: () -> RateProviderKind
    @ObservationIgnored private let logger: (String) -> Void

    init(cacheURL: URL, kind: @escaping () -> RateProviderKind, logger: @escaping (String) -> Void) {
        self.cacheURL = cacheURL
        self.kind = kind
        self.logger = logger
        if let d = try? Data(contentsOf: cacheURL) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .secondsSince1970
            table = try? dec.decode(RateTable.self, from: d)
        }
    }

    var isOffline: Bool { lastError != nil && table != nil }

    func refreshIfNeeded(maxAge: TimeInterval) {
        if let t = table, Date().timeIntervalSince(t.fetchedAt) < maxAge, lastError == nil { return }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let k = kind()
        Task { @MainActor in
            defer { isRefreshing = false }
            do {
                let t = try await RateProviders.fetch(k)
                table = t
                lastError = nil
                let enc = JSONEncoder()
                enc.dateEncodingStrategy = .secondsSince1970
                if let d = try? enc.encode(t) { try? d.write(to: cacheURL) }
            } catch {
                lastError = error.localizedDescription
                logger("rate refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func clearErrorAndRefresh() { lastError = nil; refresh() }
}

public final class CurrencyPlugin: ErgoPlugin {
    public static var manifest: PluginManifest {
        PluginManifest(
            id: "ergo.currency", name: "汇率",
            summary: "输入 $100、100 usd、100 美元 等查看实时换算（数据每日更新）",
            symbolName: "dollarsign.arrow.circlepath"
        )
    }

    private var provider: CurrencyProvider?
    private var settings: SettingsBox<CurrencySettings>?
    private var store: RateStore?

    public required init() {}

    public func activate(context: any PluginContext) async throws {
        let box = SettingsBox(store: context.settings, key: "main", default: CurrencySettings())
        settings = box
        let logger = context.logger
        let rs = RateStore(cacheURL: context.dataDirectory.appendingPathComponent("rates.json"), kind: { box.value.provider }, logger: { logger.error("\($0)") })
        store = rs
        rs.refreshIfNeeded(maxAge: TimeInterval(box.value.refreshMinutes * 60))
        provider = CurrencyProvider(context: context, settings: box, store: rs)
    }

    public func deactivate() async {
        provider = nil
        store = nil
        settings = nil
    }

    public var searchProvider: (any SearchProvider)? { provider }

    public func makeSettingsView() -> AnyView? {
        guard let settings, let store else { return nil }
        return AnyView(CurrencySettingsView(settings: settings, store: store))
    }
}

@MainActor
final class CurrencyProvider: SearchProvider {
    let participation: SearchParticipation = .global
    let tier: ResultTier = .instant
    private let context: any PluginContext
    private let settings: SettingsBox<CurrencySettings>
    private let store: RateStore

    init(context: any PluginContext, settings: SettingsBox<CurrencySettings>, store: RateStore) {
        self.context = context
        self.settings = settings
        self.store = store
    }

    static let defaultCodes: Set<String> = ["USD", "CNY", "EUR", "JPY", "GBP", "HKD", "KRW", "SGD", "AUD", "CAD", "CHF", "TWD", "THB", "RUB", "INR", "NZD", "MYR"]

    private var knownCodes: Set<String> { store.table?.codes ?? Self.defaultCodes }

    func canHandle(_ query: SearchQuery) -> Bool {
        guard let f = query.text.first, query.text.count <= 80 else { return false }
        // 以符号或数字开头，才可能是货币查询
        return f.isNumber || "$¥￥€£₩hH.".contains(f)
    }

    func search(_ query: SearchQuery) async throws -> SearchOutput {
        guard let parsed = CurrencyQueryParser.parse(query.text, knownCodes: knownCodes, yenIsJPY: settings.value.yenIsJPY) else { return .none }
        store.refreshIfNeeded(maxAge: TimeInterval(settings.value.refreshMinutes * 60))
        let state = CurrencyPanelState(parsed: parsed, store: store, favorites: settings.value.favorites, context: context)
        return .panel(InlinePanel(
            id: "currency", height: 170, exclusive: true,
            view: AnyView(CurrencyPanelView(state: state)),
            handleKey: { state.handle($0) }
        ))
    }
}

@MainActor
@Observable
final class CurrencyPanelState {
    let parsed: ParsedCurrencyQuery
    let store: RateStore
    let favorites: [String]
    var selected = 0
    private let context: any PluginContext

    init(parsed: ParsedCurrencyQuery, store: RateStore, favorites: [String], context: any PluginContext) {
        self.parsed = parsed
        self.store = store
        self.favorites = favorites
        self.context = context
    }

    struct Card: Identifiable {
        var id: String { code }
        var code: String
        var value: Double
        var rate: Double
    }

    var targets: [String] {
        if let t = parsed.target { return [t] }
        return favorites.filter { $0 != parsed.source }
    }

    var cards: [Card] {
        guard let table = store.table else { return [] }
        return targets.compactMap { c in
            guard let v = table.convert(parsed.amount, from: parsed.source, to: c), let r = table.rate(from: parsed.source, to: c) else { return nil }
            return Card(code: c, value: v, rate: r)
        }
    }

    func handle(_ press: KeyStroke) -> Bool {
        let cs = cards
        guard !cs.isEmpty else { return false }
        let mods = press.modifiers
        switch press.key {
        case .left where mods.isEmpty: selected = max(0, selected - 1); return true
        case .right where mods.isEmpty: selected = min(cs.count - 1, selected + 1); return true
        case .tab where mods.isEmpty: selected = min(cs.count - 1, selected + 1); return true
        case .tab where mods == .shift: selected = max(0, selected - 1); return true
        case .enter:
            let card = cs[min(selected, cs.count - 1)]
            let text = CurrencyFormat.plain(card.value, code: card.code)
            if mods.isEmpty {
                context.pasteboard.copy(.text(text), marker: nil)
                context.hud.show("已复制 \(text)", symbol: "checkmark.circle")
                context.launcher.hide()
                return true
            }
            if mods == .command {
                let ctx = context
                context.launcher.hide()
                Task { _ = await ctx.pasteboard.paste(.text(text), marker: nil, restoreClipboard: true) }
                return true
            }
            return false
        default:
            return false
        }
    }
}

struct CurrencyPanelView: View {
    let state: CurrencyPanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let cards = state.cards
            if cards.isEmpty {
                VStack(spacing: 8) {
                    if state.store.isRefreshing { ProgressView().controlSize(.small); Text("正在获取汇率…") }
                    else { Image(systemName: "wifi.slash"); Text(state.store.lastError ?? "暂无汇率数据") }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                                CurrencyCardView(card: card, source: state.parsed.source, isSelected: idx == state.selected)
                                    .id(card.id)
                                    .onTapGesture { state.selected = idx }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .onChange(of: state.selected) { _, new in
                        guard cards.indices.contains(new) else { return }
                        withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(cards[new].id, anchor: .center) }
                    }
                }
            }
            footer
        }
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let t = state.store.table {
                Text("\(t.providerName) · \(t.sourceDate) · 非实时，每日更新")
            }
            if state.store.isOffline, let t = state.store.table {
                Text("· 离线，使用 \(FormatHelpers.relativeDateTime(t.fetchedAt)) 的汇率").foregroundStyle(.orange)
            }
            Spacer()
            Text("←→ 切换  ↩ 复制  ⌘↩ 粘贴")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
    }
}

struct CurrencyCardView: View {
    let card: CurrencyPanelState.Card
    let source: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(CurrencyFormat.flag(card.code)).font(.system(size: 18))
                Text(card.code).font(.system(size: 13, weight: .semibold))
                Text(CurrencyFormat.chineseName(card.code)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(CurrencyFormat.display(card.value, code: card.code))
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5)
            Text("1 \(source) = \(rateString) \(card.code)")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.code)，\(CurrencyFormat.display(card.value, code: card.code))")
    }

    private var rateString: String {
        card.rate >= 100 ? String(format: "%.2f", card.rate) : String(format: "%.4f", card.rate)
    }
}

struct CurrencySettingsView: View {
    @Bindable var settings: SettingsBox<CurrencySettings>
    let store: RateStore
    @State private var newCode = ""

    var body: some View {
        Group {
            Section("数据源") {
                Picker("来源", selection: $settings.value.provider) {
                    ForEach(RateProviderKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.value.provider) { _, _ in store.clearErrorAndRefresh() }
                Picker("自动刷新", selection: $settings.value.refreshMinutes) {
                    Text("30 分钟").tag(30)
                    Text("1 小时").tag(60)
                    Text("6 小时").tag(360)
                    Text("24 小时").tag(1440)
                }
                HStack {
                    if let t = store.table { Text("最近更新：\(t.sourceDate)（\(t.providerName)）").foregroundStyle(.secondary) }
                    Spacer()
                    Button("立即刷新") { store.clearErrorAndRefresh() }
                }
                Text("免费数据源每个工作日更新一次，并非逐笔实时汇率。ExchangeRate-API 需标注来源。").font(.caption).foregroundStyle(.secondary)
            }
            Section("符号") {
                Toggle("“¥”表示日元（默认为人民币）", isOn: $settings.value.yenIsJPY)
            }
            Section("收藏币种（按顺序显示）") {
                ForEach(Array(settings.value.favorites.enumerated()), id: \.offset) { idx, code in
                    HStack {
                        Text("\(CurrencyFormat.flag(code)) \(code)  \(CurrencyFormat.chineseName(code))")
                        Spacer()
                        Button { if idx > 0 { settings.value.favorites.swapAt(idx, idx - 1) } } label: { Image(systemName: "arrow.up") }
                            .buttonStyle(.borderless).accessibilityLabel("上移").disabled(idx == 0)
                        Button { if idx < settings.value.favorites.count - 1 { settings.value.favorites.swapAt(idx, idx + 1) } } label: { Image(systemName: "arrow.down") }
                            .buttonStyle(.borderless).accessibilityLabel("下移").disabled(idx == settings.value.favorites.count - 1)
                        Button(role: .destructive) { settings.value.favorites.remove(at: idx) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("移除")
                    }
                }
                HStack {
                    TextField("添加币种代码，如 CHF", text: $newCode)
                    Button("添加") {
                        let c = newCode.trimmingCharacters(in: .whitespaces).uppercased()
                        if c.count == 3, !settings.value.favorites.contains(c) { settings.value.favorites.append(c) }
                        newCode = ""
                    }
                }
            }
        }
    }
}
