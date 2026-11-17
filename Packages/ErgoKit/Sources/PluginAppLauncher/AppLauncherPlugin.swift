import AppKit
import SwiftUI
import ErgoPluginKit
import ErgoPluginSupport
import ErgoUI

public nonisolated struct AppLauncherSettings: Codable, Equatable, Sendable {
    public var directories: [String] = AppIndexer.defaultDirectories
    public var depth: Int = 2
    public var excluded: [String] = []
    public init() {}
}

public final class AppLauncherPlugin: ErgoPlugin {
    public static var manifest: PluginManifest {
        PluginManifest(
            id: "ergo.apps", name: "应用启动",
            summary: "输入应用名称（支持拼音、首字母）快速打开",
            symbolName: "square.grid.2x2"
        )
    }

    private var provider: AppSearchProvider?
    private var settings: SettingsBox<AppLauncherSettings>?
    private var watcher: DirectoryWatcher?
    private var reindexTask: Task<Void, Never>?
    private var context: (any PluginContext)?

    public required init() {}

    public func activate(context: any PluginContext) async throws {
        self.context = context
        let box = SettingsBox(store: context.settings, key: "main", default: AppLauncherSettings())
        settings = box
        let p = AppSearchProvider(context: context)
        provider = p

        let cache = context.cacheDirectory.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: cache), let cached = try? JSONDecoder().decode([AppEntry].self, from: data) {
            p.entries = cached
        }
        reindex()
        startWatching()
    }

    public func deactivate() async {
        watcher?.stop()
        watcher = nil
        reindexTask?.cancel()
        provider = nil
        settings = nil
    }

    public var searchProvider: (any SearchProvider)? { provider }

    private func startWatching() {
        watcher?.stop()
        guard let settings else { return }
        let paths = settings.value.directories.map(AppIndexer.expand).filter { FileManager.default.fileExists(atPath: $0) }
        watcher = DirectoryWatcher(paths: paths, latency: 2) { [weak self] in
            Task { @MainActor in self?.scheduleReindex() }
        }
    }

    private func scheduleReindex() {
        reindexTask?.cancel()
        reindexTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.reindex()
        }
    }

    func reindex() {
        guard let settings, let provider, let context else { return }
        let s = settings.value
        let cache = context.cacheDirectory.appendingPathComponent("index.json")
        Task { @MainActor in
            let entries = await Task.detached(priority: .utility) {
                AppIndexer.scan(directories: s.directories, depth: s.depth, excludedIDs: Set(s.excluded))
            }.value
            provider.entries = entries
            context.logger.info("indexed \(entries.count) apps")
            if let data = try? JSONEncoder().encode(entries) { try? data.write(to: cache) }
        }
    }

    public func makeSettingsView() -> AnyView? {
        guard let settings else { return nil }
        return AnyView(AppLauncherSettingsView(settings: settings) { [weak self] in
            self?.startWatching()
            self?.reindex()
        })
    }
}

@MainActor
final class AppSearchProvider: SearchProvider {
    let participation: SearchParticipation = .global
    let tier: ResultTier = .primary
    var entries: [AppEntry] = []
    private let context: any PluginContext

    init(context: any PluginContext) { self.context = context }

    func canHandle(_ query: SearchQuery) -> Bool { !query.text.isEmpty }

    func search(_ query: SearchQuery) async throws -> SearchOutput {
        var scored: [(AppEntry, Double)] = []
        for e in entries {
            if let s = AppIndexer.score(query: query.text, entry: e) { scored.append((e, s)) }
        }
        scored.sort { $0.1 > $1.1 }
        let items = scored.prefix(20).map { makeItem($0.0, score: $0.1) }
        return .items(Array(items))
    }

    private func makeItem(_ e: AppEntry, score: Double) -> ResultItem {
        let url = e.url
        let ctx = context
        return ResultItem(
            id: "app:\(e.path)", title: e.name,
            subtitle: FormatHelpers.abbreviatingHome(e.path),
            icon: .appIcon(url), score: score,
            actions: [
                ResultAction(id: "open", title: "打开") {
                    let cfg = NSWorkspace.OpenConfiguration()
                    cfg.activates = true
                    do { try await NSWorkspace.shared.openApplication(at: url, configuration: cfg) } catch {
                        ctx.logger.error("open failed: \(error.localizedDescription)")
                        ctx.hud.show("无法打开 \(e.name)", symbol: "exclamationmark.triangle")
                    }
                    return .hideLauncher
                },
                ResultAction(id: "reveal", title: "在访达中显示", shortcut: KeyStroke(key: .enter, modifiers: .command)) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    return .hideLauncher
                },
                ResultAction(id: "copyPath", title: "复制路径", shortcut: KeyStroke(key: .character("c"), modifiers: [.command, .shift])) {
                    ctx.pasteboard.copy(.text(e.path), marker: nil)
                    ctx.hud.show("已复制路径", symbol: "checkmark.circle")
                    return .hideLauncher
                },
            ]
        )
    }
}

struct AppLauncherSettingsView: View {
    @Bindable var settings: SettingsBox<AppLauncherSettings>
    let apply: () -> Void

    var body: some View {
        Section {
            ForEach(Array(settings.value.directories.enumerated()), id: \.offset) { idx, dir in
                HStack {
                    Text(dir).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(role: .destructive) {
                        settings.value.directories.remove(at: idx)
                        apply()
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("移除目录")
                }
            }
            HStack {
                Button("添加目录…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        for u in panel.urls where !settings.value.directories.contains(u.path) {
                            settings.value.directories.append(u.path)
                        }
                        apply()
                    }
                }
                Button("恢复默认") {
                    settings.value.directories = AppIndexer.defaultDirectories
                    apply()
                }
                Button("重新索引", action: apply)
            }
            Stepper("递归深度 \(settings.value.depth)", value: $settings.value.depth, in: 0...5)
        } header: {
            Text("应用搜索范围")
        } footer: {
            Text("默认只搜索 Applications 目录及系统应用目录。")
        }
    }
}
