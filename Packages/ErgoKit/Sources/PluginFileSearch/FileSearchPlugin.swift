import AppKit
import SwiftUI
import ErgoPluginKit
import ErgoPluginSupport
import ErgoUI

public final class FileSearchPlugin: ErgoPlugin {
    public static var manifest: PluginManifest {
        PluginManifest(
            id: "ergo.files", name: "文件搜索",
            summary: "输入 f 空格 或 ' 搜索文件；没有其他结果时自动补充最多 5 条",
            symbolName: "doc.text.magnifyingglass",
            permissions: [PermissionRequirement(permission: .fullDiskAccess, reason: "用于搜索受保护的目录", isRequired: false)],
            keywords: [KeywordTrigger(text: "f"), KeywordTrigger(text: "'", requiresSpace: false)]
        )
    }

    private var context: (any PluginContext)?
    private var settings: SettingsBox<FileSearchSettings>?
    private var provider: FileSearchProvider?

    public required init() {}

    public func activate(context: any PluginContext) async throws {
        self.context = context
        let box = SettingsBox(store: context.settings, key: "main", default: FileSearchSettings())
        settings = box
        provider = FileSearchProvider(context: context, settings: box)
    }

    public func deactivate() async {
        provider = nil
        settings = nil
    }

    public var searchProvider: (any SearchProvider)? { provider }

    public func makeScope() -> (any PluginScope)? {
        guard let context, let settings else { return nil }
        return FileSearchScope(context: context, settings: settings)
    }

    public func makeSettingsView() -> AnyView? {
        guard let settings, let context else { return nil }
        return AnyView(FileSearchSettingsView(settings: settings, context: context))
    }
}

@MainActor
enum FileItemFactory {
    static func relativeTime(_ d: Date?) -> String? {
        guard let d else { return nil }
        return FormatHelpers.relativeDateTime(d)
    }

    static func makeItem(_ hit: FileHit, score: Double, context: any PluginContext) -> ResultItem {
        let url = hit.url
        let ctx = context
        let parent = FormatHelpers.abbreviatingHome((hit.path as NSString).deletingLastPathComponent)
        return ResultItem(
            id: "file:\(hit.path)", title: hit.displayName, subtitle: parent,
            icon: .fileIcon(url), accessoryText: relativeTime(hit.modified ?? hit.lastUsed), score: score,
            actions: [
                ResultAction(id: "open", title: "打开") {
                    NSWorkspace.shared.open(url)
                    return .hideLauncher
                },
                ResultAction(id: "reveal", title: "在访达中显示", shortcut: KeyStroke(key: .enter, modifiers: .command)) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    return .hideLauncher
                },
                ResultAction(id: "copyFile", title: "复制文件", shortcut: KeyStroke(key: .character("c"), modifiers: .command)) {
                    ctx.pasteboard.copy(.fileURLs([url]), marker: nil)
                    ctx.hud.show("已复制文件", symbol: "checkmark.circle")
                    return .hideLauncher
                },
                ResultAction(id: "copyPath", title: "复制路径", shortcut: KeyStroke(key: .character("c"), modifiers: [.command, .shift])) {
                    ctx.pasteboard.copy(.text(hit.path), marker: nil)
                    ctx.hud.show("已复制路径", symbol: "checkmark.circle")
                    return .hideLauncher
                },
            ],
            preview: {
                AnyView(VStack(spacing: 0) {
                    Text(FormatHelpers.abbreviatingHome(hit.path))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Divider()
                    QuickLookPreview(url: url)
                })
            }
        )
    }
}

@MainActor
final class FileSearchProvider: SearchProvider {
    let participation: SearchParticipation = .fallback(maxItems: 5, minQueryLength: 2)
    let tier: ResultTier = .fallback
    private let context: any PluginContext
    private let settings: SettingsBox<FileSearchSettings>
    private let searcher = SpotlightSearcher()

    init(context: any PluginContext, settings: SettingsBox<FileSearchSettings>) {
        self.context = context
        self.settings = settings
    }

    func canHandle(_ query: SearchQuery) -> Bool { query.text.count >= 2 }

    func search(_ query: SearchQuery) async throws -> SearchOutput {
        try await Task.sleep(for: .milliseconds(150))
        // 被超时取消时，searcher 会提前返回已收集的结果，这里照常返回。
        let hits = await searcher.search(text: query.text, settings: settings.value, limit: 60)
        let ranked = hits.map { ($0, FileQuery.score($0, query: query.text) + context.usage.boost(itemID: "ergo.files|file:\($0.path)", query: query.normalized)) }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
        return .items(ranked.map { FileItemFactory.makeItem($0.0, score: $0.1, context: context) })
    }
}

@MainActor
final class FileSearchScope: PluginScope {
    let title = "文件"
    let placeholder = "搜索文件名…"
    let style: ScopeStyle = .listWithPreview(previewRatio: 0.5)
    private let context: any PluginContext
    private let settings: SettingsBox<FileSearchSettings>
    private let searcher = SpotlightSearcher()

    init(context: any PluginContext, settings: SettingsBox<FileSearchSettings>) {
        self.context = context
        self.settings = settings
    }

    func items(for query: SearchQuery) async throws -> [ResultItem] {
        guard !query.text.isEmpty else { return [] }
        try await Task.sleep(for: .milliseconds(150))
        let hits = await searcher.search(text: query.text, settings: settings.value)
        try Task.checkCancellation()
        let ctx = context
        return hits
            .map { ($0, FileQuery.score($0, query: query.text) + ctx.usage.boost(itemID: "ergo.files|file:\($0.path)", query: query.normalized)) }
            .sorted { $0.1 > $1.1 }
            .prefix(30)
            .map { FileItemFactory.makeItem($0.0, score: $0.1, context: ctx) }
    }

    func didClose() { searcher.cancel() }
}

struct FileSearchSettingsView: View {
    @Bindable var settings: SettingsBox<FileSearchSettings>
    let context: any PluginContext

    var body: some View {
        Group {
            Section("范围") {
                Toggle("仅搜索主目录", isOn: $settings.value.homeOnly)
                Toggle("同时搜索文件内容", isOn: $settings.value.searchContent)
            }
            Section {
                ForEach(Array(settings.value.excludedPatterns.enumerated()), id: \.offset) { idx, p in
                    HStack {
                        Text(p).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) { settings.value.excludedPatterns.remove(at: idx) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("移除")
                    }
                }
                HStack {
                    Button("添加目录…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let u = panel.url, !settings.value.excludedPatterns.contains(u.path) {
                            settings.value.excludedPatterns.append(u.path)
                        }
                    }
                    Button("恢复默认") { settings.value.excludedPatterns = FileQuery.defaultExclusions }
                }
            } header: {
                Text("排除的路径")
            } footer: {
                Text("支持 ~ 缩写，以及形如 */node_modules/* 的包含匹配。")
            }
            if context.permissions.status(.fullDiskAccess) != .granted {
                Section {
                    Button("授予完全磁盘访问…") { context.permissions.openSystemSettings(for: .fullDiskAccess) }
                } footer: {
                    Text("可选。授予后可以搜索受保护的目录。")
                }
            }
        }
    }
}
