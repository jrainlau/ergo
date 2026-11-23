import AppKit
import Observation
import SwiftUI
import ErgoCore
import ErgoPluginKit
import ErgoUI

public struct DisplayItem: Identifiable {
    public let id: String
    public let pluginID: PluginID
    public let item: ResultItem
}

public struct ActiveScope {
    public let pluginID: PluginID
    public let name: String
    public let scope: any PluginScope
    public let customView: AnyView?
}

@MainActor
@Observable
public final class LauncherModel {
    // MARK: 状态
    public var query = "" {
        didSet {
            if !suppressQueryChange, query != oldValue { queryDidChange() }
        }
    }
    public internal(set) var scope: ActiveScope?
    public private(set) var results: [DisplayItem] = []
    public var selectedIndex = 0
    public private(set) var inlinePanel: (pluginID: PluginID, panel: InlinePanel)?
    public var showActionPanel = false
    public var actionSelection = 0

    // MARK: 依赖
    @ObservationIgnored let host: PluginHost
    @ObservationIgnored let services: CoreServices
    @ObservationIgnored var settings: AppSettings { services.appSettings }

    // MARK: 回调
    @ObservationIgnored public var requestHide: () -> Void = {}
    @ObservationIgnored public var requestOpenSettings: () -> Void = {}
    @ObservationIgnored public var onLayoutChange: () -> Void = {}
    /// 右上角入口右键时弹出菜单，由 AppDelegate 注入菜单栏菜单。
    @ObservationIgnored public var contextMenuProvider: (() -> NSMenu)?

    // MARK: 内部
    @ObservationIgnored weak var textField: NSTextField?
    @ObservationIgnored private var suppressQueryChange = false
    @ObservationIgnored private var sequence: UInt64 = 0
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var providerItems: [PluginID: (tier: ResultTier, items: [ResultItem])] = [:]
    @ObservationIgnored private var pendingPrimary = 0
    @ObservationIgnored private var trailingIDs: Set<PluginID> = []
    @ObservationIgnored private var selectionAnchorID: String?
    @ObservationIgnored var lastMouseLocation: NSPoint = .zero

    public init(host: PluginHost, services: CoreServices) {
        self.host = host
        self.services = services
    }

    // MARK: 布局
    public var panelWidth: CGFloat {
        if let s = scope {
            switch s.scope.style {
            case .custom: return LauncherMetrics.customWidth
            case .listWithPreview: return max(CGFloat(settings.value.panelWidth), LauncherMetrics.previewMinWidth)
            case .list: break
            }
        }
        return CGFloat(settings.value.panelWidth)
    }

    var showsHostInput: Bool {
        if let s = scope, case .custom(_, let shows) = s.scope.style { return shows }
        return true
    }

    public var panelHeight: CGFloat {
        let input = Theme.inputHeight
        if let s = scope {
            switch s.scope.style {
            case .custom(let h, _): return h
            case .listWithPreview:
                return input + 1 + Theme.listPadding + CGFloat(LauncherMetrics.previewRows) * Theme.rowHeight + Theme.listPadding
            case .list: break
            }
        }
        var h = input
        if let p = inlinePanel {
            h += 1 + p.panel.height
            if p.panel.exclusive { return h }
        }
        if !results.isEmpty {
            let rows = min(results.count, settings.value.maxVisibleRows)
            h += 1 + Theme.listPadding + CGFloat(rows) * Theme.rowHeight + Theme.listPadding
        }
        return h
    }

    // MARK: 生命周期
    public func resetForShow(keepQuery: Bool) {
        exitScope(silently: true)
        showActionPanel = false
        selectionAnchorID = nil
        if !keepQuery {
            setQuerySilently("")
            clearResults()
        } else {
            refresh()
        }
        lastMouseLocation = NSEvent.mouseLocation
        onLayoutChange()
    }

    public func didHide() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        exitScope(silently: true)
        showActionPanel = false
    }

    private func setQuerySilently(_ s: String) {
        suppressQueryChange = true
        query = s
        suppressQueryChange = false
    }

    // MARK: 作用域
    public func enterScope(_ id: PluginID, query newQuery: String) {
        guard let reg = host.registration(for: id), let sc = host.makeScope(for: id) else { return }
        exitScope(silently: true)
        var custom: AnyView?
        if case .custom = sc.style { custom = sc.makeCustomView() }
        scope = ActiveScope(pluginID: id, name: reg.manifest.name, scope: sc, customView: custom)
        setQuerySilently(newQuery)
        clearResults()
        refresh()
        onLayoutChange()
    }

    public func exitScope(silently: Bool = false) {
        guard let s = scope else { return }
        s.scope.didClose()
        scope = nil
        if !silently {
            setQuerySilently("")
            clearResults()
            onLayoutChange()
        }
    }

    // MARK: 查询
    private func queryDidChange() {
        showActionPanel = false
        if scope == nil, let m = host.matchKeyword(query), m.registration.instance?.makeScope() != nil {
            enterScope(m.registration.id, query: m.remainder)
            return
        }
        selectionAnchorID = nil
        refresh()
    }

    private func clearResults() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        sequence += 1
        providerItems = [:]
        results = []
        inlinePanel = nil
        selectedIndex = 0
        selectionAnchorID = nil
    }

    public func refresh() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        sequence += 1
        let seq = sequence
        let sq = SearchQuery(sequence: seq, raw: query)

        if let s = scope {
            let sc = s.scope
            let pid = s.pluginID
            let t = Task { @MainActor [weak self] in
                let items = (try? await sc.items(for: sq)) ?? []
                guard let self, !Task.isCancelled, self.sequence == seq else { return }
                self.providerItems = [pid: (.primary, items)]
                self.inlinePanel = nil
                self.rebuild(query: sq, keepSelection: true)
            }
            tasks.append(t)
            return
        }

        providerItems = [:]
        inlinePanel = nil
        guard !sq.text.isEmpty else {
            results = []
            selectedIndex = 0
            onLayoutChange()
            return
        }

        var primary: [(PluginID, any SearchProvider)] = []
        var fallbacks: [(PluginID, any SearchProvider, Int, Int)] = []
        var trailing: [(PluginID, any SearchProvider)] = []
        for reg in host.activeRegistrations {
            guard let p = reg.instance?.searchProvider, p.canHandle(sq) else { continue }
            switch p.participation {
            case .global: primary.append((reg.id, p))
            case .fallback(let maxItems, let minLen): fallbacks.append((reg.id, p, maxItems, minLen))
            case .trailing: trailing.append((reg.id, p))
            case .none: break
            }
        }
        pendingPrimary = primary.count
        trailingIDs = Set(trailing.map(\.0))
        runTrailing(trailing, sq: sq, seq: seq)
        if primary.isEmpty { runFallbacks(fallbacks, sq: sq, seq: seq); return }

        for (pid, provider) in primary {
            let t = Task { @MainActor [weak self] in
                let out = await Self.runWithTimeout(provider, sq)
                guard let self, !Task.isCancelled, self.sequence == seq else { return }
                switch out {
                case .items(let items): self.providerItems[pid] = (provider.tier, items)
                case .panel(let p): self.inlinePanel = (pid, p)
                case .none: break
                }
                self.pendingPrimary -= 1
                self.rebuild(query: sq, keepSelection: true)
                if self.pendingPrimary == 0, !self.hasPrimaryHit, self.inlinePanel == nil {
                    self.runFallbacks(fallbacks, sq: sq, seq: seq)
                }
            }
            tasks.append(t)
        }
    }

    /// 是否已有“强命中”（不计 `.trailing` 的结果）。
    private var hasPrimaryHit: Bool {
        providerItems.contains { !trailingIDs.contains($0.key) && !$0.value.items.isEmpty }
    }

    private static func runWithTimeout(_ provider: any SearchProvider, _ sq: SearchQuery, timeout: Duration = .milliseconds(1500)) async -> SearchOutput {
        let work = Task { @MainActor in try? await provider.search(sq) }
        let timer = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            work.cancel()
        }
        let r = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
            timer.cancel()
        }
        timer.cancel()
        return r ?? .none
    }

    private func runTrailing(_ list: [(PluginID, any SearchProvider)], sq: SearchQuery, seq: UInt64) {
        for (pid, provider) in list {
            let t = Task { @MainActor [weak self] in
                let out = await Self.runWithTimeout(provider, sq, timeout: .seconds(20))
                guard let self, !Task.isCancelled, self.sequence == seq else { return }
                if case .items(let items) = out, !items.isEmpty {
                    self.providerItems[pid] = (provider.tier, items)
                    self.rebuild(query: sq, keepSelection: true)
                }
            }
            tasks.append(t)
        }
    }

    private func runFallbacks(_ list: [(PluginID, any SearchProvider, Int, Int)], sq: SearchQuery, seq: UInt64) {
        for (pid, provider, maxItems, minLen) in list where sq.text.count >= minLen {
            let t = Task { @MainActor [weak self] in
                let out = await Self.runWithTimeout(provider, sq)
                guard let self, !Task.isCancelled, self.sequence == seq else { return }
                if case .items(let items) = out {
                    self.providerItems[pid] = (.fallback, Array(items.prefix(maxItems)))
                    self.rebuild(query: sq, keepSelection: true)
                }
            }
            tasks.append(t)
        }
    }

    private func rebuild(query sq: SearchQuery, keepSelection: Bool) {
        var merged: [(DisplayItem, Double, ResultTier)] = []
        for (pid, entry) in providerItems {
            for item in entry.items {
                let full = "\(pid.rawValue)|\(item.id)"
                let boost = services.usage.boost(itemID: full, query: sq.normalized)
                let score = scope == nil ? item.score * 0.8 + boost : item.score
                merged.append((DisplayItem(id: full, pluginID: pid, item: item), score, entry.tier))
            }
        }
        if scope == nil {
            merged.sort { a, b in a.2 != b.2 ? a.2 < b.2 : a.1 > b.1 }
        } else {
            // 作用域内保持插件给出的顺序
            let order = providerItems.values.first?.items.map(\.id) ?? []
            let idx = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            merged.sort { (idx[$0.0.item.id] ?? 0) < (idx[$1.0.item.id] ?? 0) }
        }
        let anchor = selectionAnchorID ?? (keepSelection && !results.isEmpty && selectedIndex < results.count ? results[selectedIndex].id : nil)
        results = merged.map(\.0)
        if let anchor, let i = results.firstIndex(where: { $0.id == anchor }) {
            selectedIndex = i
        } else {
            selectedIndex = 0
        }
        lastMouseLocation = NSEvent.mouseLocation
        onLayoutChange()
    }

    // MARK: 选择与执行
    public var selectedItem: DisplayItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    public func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let n = results.count
        selectedIndex = ((selectedIndex + delta) % n + n) % n
        selectionAnchorID = results[selectedIndex].id
    }

    public func hover(_ index: Int) {
        let loc = NSEvent.mouseLocation
        guard loc != lastMouseLocation else { return }
        lastMouseLocation = loc
        selectedIndex = index
        selectionAnchorID = results.indices.contains(index) ? results[index].id : nil
    }

    public func perform(_ action: ResultAction, on item: DisplayItem) {
        let q = query
        Task { @MainActor [weak self] in
            let outcome = await action.perform()
            guard let self else { return }
            self.services.usage.record(itemID: item.id, query: SearchQuery.normalize(q.trimmingCharacters(in: .whitespaces)))
            self.apply(outcome)
        }
    }

    public func activate(index: Int) {
        guard results.indices.contains(index), let a = results[index].item.actions.first else { return }
        perform(a, on: results[index])
    }

    func apply(_ outcome: ActionOutcome) {
        showActionPanel = false
        switch outcome {
        case .hideLauncher: requestHide()
        case .keepOpen: break
        case .setQuery(let s): query = s
        case .refresh: refresh()
        case .openScope(let id): enterScope(id, query: "")
        }
    }

    // MARK: 按键
    /// 返回 true 表示按键已处理（事件被吞掉）。
    public func handle(_ press: KeyStroke) -> Bool {
        if showActionPanel { return handleActionPanel(press) }
        if let s = scope, s.scope.handleKey(press) { return true }
        if let p = inlinePanel, p.panel.handleKey(press) { return true }
        // 自带输入框的自定义作用域（如 AI 对话）：其余按键交给它自己的文本框
        if let s = scope, case .custom(_, false) = s.scope.style {
            if press.key == .escape { requestHide(); return true }
            if press.modifiers == .command, press.key == .character(",") { requestOpenSettings(); return true }
            return false
        }

        let mods = press.modifiers
        // 带修饰键的快捷键：优先匹配选中项的动作
        if !mods.isEmpty, let item = selectedItem, let a = item.item.actions.first(where: { $0.shortcut == press }) {
            perform(a, on: item)
            return true
        }
        switch press.key {
        case .up where mods.isEmpty: move(-1); return true
        case .down where mods.isEmpty: move(1); return true
        case .pageUp where mods.isEmpty: move(-5); return true
        case .pageDown where mods.isEmpty: move(5); return true
        case .escape:
            if !query.isEmpty { query = ""; return true }
            requestHide()
            return true
        case .deleteBackward where mods.isEmpty && query.isEmpty && scope != nil:
            exitScope()
            return true
        case .enter:
            guard let item = selectedItem else { return false }
            if let a = item.item.actions.first(where: { $0.shortcut == press }) {
                perform(a, on: item); return true
            }
            if mods.isEmpty, let a = item.item.actions.first { perform(a, on: item); return true }
            return false
        case .character(let c):
            if mods == .command {
                if let n = c.wholeNumberValue, (1...9).contains(n) {
                    activate(index: n - 1); return true
                }
                if c == "k" {
                    guard let item = selectedItem, item.item.actions.count > 0 else { return true }
                    showActionPanel = true; actionSelection = 0; return true
                }
                if c == "," { requestOpenSettings(); return true }
            }
            if let item = selectedItem, let a = item.item.actions.first(where: { $0.shortcut == press }) {
                perform(a, on: item); return true
            }
            return false
        default:
            return false
        }
    }

    private func handleActionPanel(_ press: KeyStroke) -> Bool {
        guard let item = selectedItem else { showActionPanel = false; return true }
        let n = item.item.actions.count
        switch press.key {
        case .up: actionSelection = (actionSelection - 1 + n) % n
        case .down: actionSelection = (actionSelection + 1) % n
        case .escape: showActionPanel = false
        case .enter:
            if actionSelection < n { perform(item.item.actions[actionSelection], on: item) }
            showActionPanel = false
        case .character("k") where press.modifiers == .command: showActionPanel = false
        default: break
        }
        return true
    }
}
