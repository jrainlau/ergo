import AppKit
import SwiftUI
import ErgoPluginKit
import ErgoPluginSupport
import ErgoUI

public final class ClipboardPlugin: ErgoPlugin {
    public static var manifest: PluginManifest {
        PluginManifest(
            id: "ergo.clipboard", name: "剪贴板",
            summary: "记录一段时间内的文字、图片、文件等剪贴板历史，支持搜索与预览",
            symbolName: "list.clipboard",
            permissions: [
                PermissionRequirement(permission: .pasteboard, reason: "读取剪贴板内容以记录历史"),
                PermissionRequirement(permission: .accessibility, reason: "选中后直接粘贴到前台应用", isRequired: false),
                PermissionRequirement(permission: .inputMonitoring, reason: "使用“双击 Control”唤起", isRequired: false),
            ],
            keywords: [KeywordTrigger(text: "cb")],
            hotkeys: [HotkeyActionDescriptor(id: "clipboard.open", title: "唤起剪贴板", defaultTrigger: .doubleTap(.control))]
        )
    }

    var context: (any PluginContext)?
    var settings: SettingsBox<ClipboardSettings>?
    var store: ClipboardStore?
    private var monitor: ClipboardMonitor?
    private var cleanupTimer: Timer?

    public required init() {}

    public func activate(context: any PluginContext) async throws {
        self.context = context
        let box = SettingsBox(store: context.settings, key: "main", default: ClipboardSettings())
        settings = box
        let store = try ClipboardStore(directory: context.dataDirectory)
        self.store = store

        let m = ClipboardMonitor(store: store, settings: { box.value }, onChange: { [weak context] in
            if context?.launcher.isVisible == true { context?.launcher.refresh() }
        })
        m.start()
        monitor = m

        runCleanup()
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runCleanup() }
        }
        RunLoop.main.add(t, forMode: .common)
        cleanupTimer = t
    }

    public func deactivate() async {
        monitor?.stop()
        monitor = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        store = nil
        settings = nil
    }

    func runCleanup() {
        guard let store, let s = settings?.value else { return }
        let retention = s.retention
        let max = s.maxItems
        Task.detached(priority: .utility) {
            _ = try? store.cleanup(retention: retention, maxItems: max)
        }
    }

    public func makeScope() -> (any PluginScope)? {
        guard let context, let store, let settings else { return nil }
        return ClipboardScope(context: context, store: store, settings: settings)
    }

    public func perform(hotkey: HotkeyActionID) async {
        guard let context else { return }
        if context.launcher.isVisible { context.launcher.hide() } else { context.launcher.show(scope: Self.manifest.id, query: nil) }
    }

    public func makeSettingsView() -> AnyView? {
        guard let settings, let store, let context else { return nil }
        return AnyView(ClipboardSettingsView(settings: settings, store: store, context: context))
    }
}

@MainActor
final class ClipboardScope: PluginScope {
    let title = "剪贴板"
    let placeholder = "搜索剪贴板历史…"
    let style: ScopeStyle = .listWithPreview(previewRatio: 0.55)

    private let context: any PluginContext
    private let store: ClipboardStore
    private let settings: SettingsBox<ClipboardSettings>

    init(context: any PluginContext, store: ClipboardStore, settings: SettingsBox<ClipboardSettings>) {
        self.context = context
        self.store = store
        self.settings = settings
    }

    func items(for query: SearchQuery) async throws -> [ResultItem] {
        let clips = (try? store.search(query.text)) ?? []
        return clips.map(makeItem)
    }

    private func makeItem(_ clip: ClipItem) -> ResultItem {
        let icon: ResultIcon
        if let b = clip.sourceBundleID { icon = .bundleAppIcon(bundleID: b) } else { icon = .symbol(clip.clipKind.symbol) }
        let store = self.store
        let ctx = context
        var actions: [ResultAction] = [
            ResultAction(id: "paste", title: "粘贴") { [self] in
                guard let content = pasteContent(clip, plain: false) else { return .keepOpen }
                _ = await ctx.pasteboard.paste(content, marker: clip.id, restoreClipboard: false)
                return .hideLauncher
            },
            ResultAction(id: "copy", title: "复制", shortcut: KeyStroke(key: .enter, modifiers: .command)) { [self] in
                guard let content = pasteContent(clip, plain: false) else { return .keepOpen }
                ctx.pasteboard.copy(content, marker: clip.id)
                ctx.hud.show("已复制", symbol: "checkmark.circle")
                return .hideLauncher
            },
        ]
        if clip.clipKind == .richText || clip.clipKind == .link || clip.clipKind == .text {
            actions.append(ResultAction(id: "plain", title: "以纯文本粘贴", shortcut: KeyStroke(key: .enter, modifiers: .shift)) { [self] in
                guard let content = pasteContent(clip, plain: true) else { return .keepOpen }
                _ = await ctx.pasteboard.paste(content, marker: clip.id, restoreClipboard: false)
                return .hideLauncher
            })
        }
        actions.append(ResultAction(id: "pin", title: clip.isPinned ? "取消置顶" : "置顶", shortcut: KeyStroke(key: .character("p"), modifiers: .command)) {
            try? store.setPinned(clip.id, !clip.isPinned)
            return .refresh
        })
        actions.append(ResultAction(id: "delete", title: "删除", shortcut: KeyStroke(key: .deleteBackward, modifiers: .command)) {
            try? store.delete(id: clip.id)
            return .refresh
        })
        if clip.clipKind == .link, let s = clip.textContent, let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            actions.append(ResultAction(id: "open", title: "在浏览器打开", shortcut: KeyStroke(key: .character("o"), modifiers: .command)) {
                NSWorkspace.shared.open(url)
                return .hideLauncher
            })
        }
        if clip.clipKind == .file, let paths = clip.meta.paths {
            let urls = paths.map { URL(fileURLWithPath: $0) }
            actions.append(ResultAction(id: "open", title: "打开", shortcut: KeyStroke(key: .character("o"), modifiers: .command)) {
                for u in urls { NSWorkspace.shared.open(u) }
                return .hideLauncher
            })
            actions.append(ResultAction(id: "reveal", title: "在访达中显示", shortcut: KeyStroke(key: .character("r"), modifiers: .command)) {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                return .hideLauncher
            })
        }
        return ResultItem(
            id: clip.id, title: clip.title, icon: icon, score: 0.5, actions: actions,
            preview: { AnyView(ClipPreviewView(item: clip, store: store)) }
        )
    }

    func pasteContent(_ clip: ClipItem, plain: Bool) -> PasteContent? {
        switch clip.clipKind {
        case .text, .link:
            return .text(clip.textContent ?? clip.title)
        case .richText:
            if !plain, let url = store.blobURL(clip), let rtf = try? Data(contentsOf: url) {
                return .richText(rtf: rtf, plain: clip.textContent ?? clip.title)
            }
            return .text(clip.textContent ?? clip.title)
        case .image:
            guard let url = store.blobURL(clip), let data = try? Data(contentsOf: url) else { return nil }
            return .image(png: data)
        case .file:
            let existing = (clip.meta.paths ?? []).map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !existing.isEmpty { return .fileURLs(existing) }
            if let blob = store.blobURL(clip), FileManager.default.fileExists(atPath: blob.path) { return .fileURLs([blob]) }
            context.hud.show("文件已不存在", symbol: "exclamationmark.triangle")
            return nil
        case .color:
            let hex = clip.meta.colorHex ?? clip.title
            if plain { return .text(hex) }
            return ClipColor.color(fromHex: hex).map { .color($0) } ?? .text(hex)
        }
    }
}

struct ClipboardSettingsView: View {
    @Bindable var settings: SettingsBox<ClipboardSettings>
    let store: ClipboardStore
    let context: any PluginContext
    @State private var confirmClear = false

    var body: some View {
        Group {
            Section("保留") {
                Picker("保留时长", selection: $settings.value.retentionDays) {
                    Text("1 天").tag(1)
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("3 个月").tag(90)
                    Text("1 年").tag(365)
                    Text("永久").tag(0)
                }
                Stepper("最多 \(settings.value.maxItems) 条", value: $settings.value.maxItems, in: 100...50000, step: 100)
            }
            Section("记录类型") {
                Toggle("文本", isOn: $settings.value.recordText)
                Toggle("富文本", isOn: $settings.value.recordRichText)
                Toggle("图片", isOn: $settings.value.recordImage)
                Toggle("文件", isOn: $settings.value.recordFile)
                Toggle("颜色", isOn: $settings.value.recordColor)
                Stepper("文件图片副本上限 \(settings.value.imageCopyLimitMB) MB", value: $settings.value.imageCopyLimitMB, in: 1...200)
            }
            Section("监听") {
                LabeledContent(String(format: "轮询间隔 %.2f 秒", settings.value.pollInterval)) {
                    Slider(value: $settings.value.pollInterval, in: 0.25...1.0, step: 0.05).frame(width: 200)
                }
                if context.permissions.status(.pasteboard) != .granted {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("系统可能会在读取剪贴板时提示。建议在 系统设置 › 隐私与安全性 中将 Ergo 的“粘贴板”设为“始终允许”。")
                            .font(.caption).foregroundStyle(.orange)
                        Button("打开系统设置") { context.permissions.openSystemSettings(for: .pasteboard) }
                    }
                }
            }
            Section("忽略的应用") {
                ForEach(Array(settings.value.ignoredBundleIDs.enumerated()), id: \.offset) { idx, id in
                    HStack {
                        Text(id).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) { settings.value.ignoredBundleIDs.remove(at: idx) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("移除")
                    }
                }
                Button("添加应用…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK, let u = panel.url, let id = Bundle(url: u)?.bundleIdentifier,
                       !settings.value.ignoredBundleIDs.contains(id) {
                        settings.value.ignoredBundleIDs.append(id)
                    }
                }
            }
            Section {
                Button("清空剪贴板历史…", role: .destructive) { confirmClear = true }
            }
        }
        .confirmationDialog("清空所有剪贴板历史？", isPresented: $confirmClear) {
            Button("清空", role: .destructive) { try? store.deleteAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销（已置顶的记录也会被删除）。")
        }
    }
}
