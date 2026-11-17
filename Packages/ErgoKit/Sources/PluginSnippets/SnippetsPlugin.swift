import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import ErgoPluginKit
import ErgoPluginSupport
import ErgoUI

public nonisolated struct SnippetsSettings: Codable, Equatable, Sendable {
    public var showInGlobalSearch = false
    public var restoreClipboard = true
    public init() {}
}

public final class SnippetsPlugin: ErgoPlugin {
    public static var manifest: PluginManifest {
        PluginManifest(
            id: "ergo.snippets", name: "常用语",
            summary: "保存常用文本，输入 sn 搜索并一键插入；支持 {date}、{cursor} 等占位符",
            symbolName: "text.quote",
            permissions: [PermissionRequirement(permission: .accessibility, reason: "把常用语直接插入到前台应用", isRequired: false)],
            keywords: [KeywordTrigger(text: "sn")],
            hotkeys: [HotkeyActionDescriptor(id: "snippets.open", title: "唤起常用语", defaultTrigger: .none)]
        )
    }

    var context: (any PluginContext)?
    var settings: SettingsBox<SnippetsSettings>?
    var store: SnippetStore?
    var library: SnippetsLibraryModel?
    private var provider: SnippetsGlobalProvider?

    public required init() {}

    public func activate(context: any PluginContext) async throws {
        self.context = context
        let box = SettingsBox(store: context.settings, key: "main", default: SnippetsSettings())
        settings = box
        let st = try SnippetStore(path: context.dataDirectory.appendingPathComponent("snippets.sqlite").path)
        store = st
        library = SnippetsLibraryModel(store: st)
        provider = SnippetsGlobalProvider(plugin: self)
    }

    public func deactivate() async {
        provider = nil
        library = nil
        store = nil
        settings = nil
    }

    public var searchProvider: (any SearchProvider)? { provider }

    public func makeScope() -> (any PluginScope)? {
        guard let context, let store, let settings else { return nil }
        return SnippetsScope(plugin: self, context: context, store: store, settings: settings)
    }

    public func perform(hotkey: HotkeyActionID) async {
        guard let context else { return }
        if context.launcher.isVisible { context.launcher.hide() } else { context.launcher.show(scope: Self.manifest.id, query: nil) }
    }

    public func makeSettingsView() -> AnyView? {
        guard let settings else { return nil }
        return AnyView(Section("行为") {
            Toggle("在全局搜索中显示常用语", isOn: Binding(get: { settings.value.showInGlobalSearch }, set: { settings.value.showInGlobalSearch = $0 }))
            Toggle("插入后恢复原剪贴板内容", isOn: Binding(get: { settings.value.restoreClipboard }, set: { settings.value.restoreClipboard = $0 }))
        })
    }

    public func makeManagementView() -> AnyView? {
        guard let library else { return nil }
        return AnyView(SnippetsManagementView(model: library))
    }
}

@MainActor
enum SnippetItemFactory {
    static func expandedText(_ s: Snippet) -> ExpandedSnippet {
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        return SnippetExpander.expand(s.content, context: ExpansionContext(clipboard: clip))
    }

    static func makeItem(_ s: Snippet, collectionName: String?, score: Double, plugin: SnippetsPlugin, context: any PluginContext, store: SnippetStore, settings: SettingsBox<SnippetsSettings>) -> ResultItem {
        ResultItem(
            id: "snip:\(s.id)", title: s.title, subtitle: collectionName,
            icon: .symbol("text.quote"), accessoryText: s.keyword.isEmpty ? nil : s.keyword, score: score,
            actions: [
                ResultAction(id: "paste", title: "插入") {
                    let e = expandedText(s)
                    try? store.recordUse(id: s.id)
                    _ = await context.pasteboard.paste(.text(e.text), marker: nil, restoreClipboard: settings.value.restoreClipboard)
                    if let back = e.cursorBack { await context.pasteboard.postKeystrokes(leftArrowCount: back) }
                    return .hideLauncher
                },
                ResultAction(id: "copy", title: "仅复制", shortcut: KeyStroke(key: .enter, modifiers: .command)) {
                    let e = expandedText(s)
                    try? store.recordUse(id: s.id)
                    context.pasteboard.copy(.text(e.text), marker: nil)
                    context.hud.show("已复制", symbol: "checkmark.circle")
                    return .hideLauncher
                },
                ResultAction(id: "edit", title: "编辑…", shortcut: KeyStroke(key: .character("e"), modifiers: .command)) {
                    plugin.library?.focus(snippetID: s.id)
                    context.launcher.openSettings(for: SnippetsPlugin.manifest.id, openManagement: true)
                    return .hideLauncher
                },
            ],
            preview: { AnyView(SnippetPreview(snippet: s)) }
        )
    }
}

struct SnippetPreview: View {
    let snippet: Snippet
    var body: some View {
        let e = SnippetItemFactory.expandedText(snippet)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(snippet.title).font(.headline)
                Text(e.text)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if e.cursorBack != nil {
                    Label("插入后光标会移动到 {cursor} 位置", systemImage: "character.cursor.ibeam").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }
}

@MainActor
final class SnippetsScope: PluginScope {
    let title = "常用语"
    let placeholder = "搜索常用语…"
    let style: ScopeStyle = .listWithPreview(previewRatio: 0.5)
    private unowned let plugin: SnippetsPlugin
    private let context: any PluginContext
    private let store: SnippetStore
    private let settings: SettingsBox<SnippetsSettings>

    init(plugin: SnippetsPlugin, context: any PluginContext, store: SnippetStore, settings: SettingsBox<SnippetsSettings>) {
        self.plugin = plugin
        self.context = context
        self.store = store
        self.settings = settings
    }

    func items(for query: SearchQuery) async throws -> [ResultItem] {
        let cols = Dictionary(uniqueKeysWithValues: ((try? store.collections()) ?? []).map { ($0.id, $0.name) })
        let all = (try? store.snippets()) ?? []
        var scored: [(Snippet, Double)] = []
        if query.text.isEmpty {
            scored = all.map { ($0, 0.5 + SnippetMatcher.useBoost($0.useCount)) }
            scored.sort { ($0.0.useCount, $0.0.lastUsedAt ?? 0) > ($1.0.useCount, $1.0.lastUsedAt ?? 0) }
        } else {
            for s in all { if let sc = SnippetMatcher.score(query: query.text, snippet: s) { scored.append((s, sc + SnippetMatcher.useBoost(s.useCount))) } }
            scored.sort { $0.1 > $1.1 }
        }
        return scored.map { SnippetItemFactory.makeItem($0.0, collectionName: cols[$0.0.collectionID], score: $0.1, plugin: plugin, context: context, store: store, settings: settings) }
    }
}

@MainActor
final class SnippetsGlobalProvider: SearchProvider {
    let tier: ResultTier = .secondary
    private unowned let plugin: SnippetsPlugin
    init(plugin: SnippetsPlugin) { self.plugin = plugin }

    var participation: SearchParticipation { plugin.settings?.value.showInGlobalSearch == true ? .global : .none }

    func canHandle(_ query: SearchQuery) -> Bool { plugin.settings?.value.showInGlobalSearch == true && !query.text.isEmpty }

    func search(_ query: SearchQuery) async throws -> SearchOutput {
        guard let store = plugin.store, let ctx = plugin.context, let settings = plugin.settings else { return .none }
        let cols = Dictionary(uniqueKeysWithValues: ((try? store.collections()) ?? []).map { ($0.id, $0.name) })
        let items = ((try? store.snippets()) ?? []).compactMap { s -> (Snippet, Double)? in
            SnippetMatcher.score(query: query.text, snippet: s).map { (s, $0) }
        }
        .sorted { $0.1 > $1.1 }
        .prefix(5)
        .map { SnippetItemFactory.makeItem($0.0, collectionName: cols[$0.0.collectionID], score: $0.1 * 0.9, plugin: plugin, context: ctx, store: store, settings: settings) }
        return .items(Array(items))
    }
}

// MARK: - 管理界面

@MainActor
@Observable
final class SnippetsLibraryModel {
    let store: SnippetStore
    var collections: [SnippetCollection] = []
    var snippets: [Snippet] = []
    var selectedCollection: String?
    var selectedSnippet: String?
    var message: String?

    init(store: SnippetStore) {
        self.store = store
        reload()
    }

    func reload() {
        collections = (try? store.collections()) ?? []
        if selectedCollection == nil || !collections.contains(where: { $0.id == selectedCollection }) { selectedCollection = collections.first?.id }
        snippets = (try? store.snippets(in: selectedCollection)) ?? []
        if let s = selectedSnippet, !snippets.contains(where: { $0.id == s }) { selectedSnippet = nil }
    }

    func focus(snippetID: String) {
        guard let s = try? store.snippet(id: snippetID) else { return }
        selectedCollection = s.collectionID
        reload()
        selectedSnippet = snippetID
    }

    func addCollection() {
        if let c = try? store.addCollection(name: "新分组") { selectedCollection = c.id; reload() }
    }

    func deleteCollection(_ id: String) {
        try? store.deleteCollection(id: id)
        selectedCollection = nil
        reload()
    }

    func rename(_ id: String, to name: String) {
        try? store.renameCollection(id: id, name: name)
        collections = (try? store.collections()) ?? []
    }

    func addSnippet() {
        guard let c = selectedCollection, let s = try? store.addSnippet(collectionID: c, title: "新常用语") else { return }
        reload()
        selectedSnippet = s.id
    }

    func deleteSnippet(_ id: String) {
        try? store.deleteSnippet(id: id)
        reload()
    }

    func save(_ s: Snippet) {
        try? store.update(s)
        if let i = snippets.firstIndex(where: { $0.id == s.id }) { snippets[i] = s }
    }

    func move(from: IndexSet, to: Int) {
        var ids = snippets.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        try? store.reorder(ids: ids)
        reload()
    }

    func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ergo-snippets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportLibrary().write(to: url); message = "已导出" } catch { message = "导出失败：\(error.localizedDescription)" }
    }

    func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let n = try store.importLibrary(Data(contentsOf: url))
            message = "已导入 \(n) 条"
            reload()
        } catch { message = "导入失败：\(error.localizedDescription)" }
    }
}

struct SnippetsManagementView: View {
    @Bindable var model: SnippetsLibraryModel

    var body: some View {
        HSplitView {
            collectionList.frame(minWidth: 150, idealWidth: 180, maxWidth: 240)
            snippetList.frame(minWidth: 260, idealWidth: 300)
            editor.frame(minWidth: 320)
        }
        .onAppear { model.reload() }
        .onChange(of: model.selectedCollection) { _, _ in model.reload() }
    }

    private var collectionList: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedCollection) {
                ForEach(model.collections) { c in
                    Label(c.name, systemImage: "folder").tag(c.id)
                        .contextMenu {
                            Button("重命名…") { rename(c) }
                            Button("删除分组", role: .destructive) { model.deleteCollection(c.id) }
                        }
                }
            }
            Divider()
            HStack {
                Button { model.addCollection() } label: { Image(systemName: "plus") }.accessibilityLabel("新建分组")
                Button { if let id = model.selectedCollection { model.deleteCollection(id) } } label: { Image(systemName: "minus") }
                    .accessibilityLabel("删除分组").disabled(model.collections.count <= 1)
                Spacer()
                Button { if let c = model.collections.first(where: { $0.id == model.selectedCollection }) { rename(c) } } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("重命名分组")
            }
            .buttonStyle(.borderless).padding(8)
        }
    }

    private func rename(_ c: SnippetCollection) {
        let alert = NSAlert()
        alert.messageText = "重命名分组"
        let field = NSTextField(string: c.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty { model.rename(c.id, to: field.stringValue) }
    }

    private var snippetList: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedSnippet) {
                ForEach(model.snippets) { s in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.title).lineLimit(1)
                            Text(s.content.replacingOccurrences(of: "\n", with: " ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if !s.keyword.isEmpty { Text(s.keyword).font(.caption.monospaced()).foregroundStyle(.secondary) }
                        Text("\(s.useCount)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                    .tag(s.id)
                    .contextMenu { Button("删除", role: .destructive) { model.deleteSnippet(s.id) } }
                }
                .onMove { model.move(from: $0, to: $1) }
            }
            Divider()
            HStack {
                Button { model.addSnippet() } label: { Image(systemName: "plus") }.accessibilityLabel("新建常用语")
                Button { if let id = model.selectedSnippet { model.deleteSnippet(id) } } label: { Image(systemName: "minus") }
                    .accessibilityLabel("删除常用语").disabled(model.selectedSnippet == nil)
                Spacer()
                if let m = model.message { Text(m).font(.caption).foregroundStyle(.secondary) }
                Button("导入…") { model.importFromFile() }
                Button("导出…") { model.exportToFile() }
            }
            .buttonStyle(.borderless).padding(8)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let id = model.selectedSnippet, let s = model.snippets.first(where: { $0.id == id }) {
            SnippetEditor(snippet: s, collections: model.collections, onSave: { model.save($0) }, onMove: { cid in
                try? model.store.move(snippetID: s.id, to: cid)
                model.reload()
            })
            .id(id)
        } else {
            Text("选择或新建一条常用语").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SnippetEditor: View {
    @State var snippet: Snippet
    let collections: [SnippetCollection]
    let onSave: (Snippet) -> Void
    let onMove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("标题", text: $snippet.title).textFieldStyle(.roundedBorder)
            HStack {
                TextField("关键词（可选）", text: $snippet.keyword).textFieldStyle(.roundedBorder)
                Picker("分组", selection: Binding(get: { snippet.collectionID }, set: { snippet.collectionID = $0; onMove($0) })) {
                    ForEach(collections) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().frame(width: 140)
            }
            HStack {
                Text("内容").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("插入占位符") {
                    ForEach(SnippetExpander.placeholders, id: \.token) { p in
                        Button("\(p.token)  \(p.title)") { snippet.content += p.token }
                    }
                }
                .fixedSize()
            }
            TextEditor(text: $snippet.content)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            Text("用 {{ 和 }} 输入字面花括号。已使用 \(snippet.useCount) 次。").font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .onChange(of: snippet.title) { _, _ in onSave(snippet) }
        .onChange(of: snippet.keyword) { _, _ in onSave(snippet) }
        .onChange(of: snippet.content) { _, _ in onSave(snippet) }
    }
}
