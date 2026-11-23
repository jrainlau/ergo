import AppKit
import SwiftUI
import Translation
import ErgoPluginKit

struct TranslateSettingsView: View {
    @Bindable var settings: SettingsBox<TranslateSettings>
    let context: any PluginContext
    @State private var editing: LLMEngineConfig?
    @State private var isNew = false

    var body: some View {
        Group {
            Section {
                Toggle("输入文字时自动翻译", isOn: $settings.value.autoInSearch)
                Stepper("只翻译不超过 \(settings.value.searchMaxChars) 个字符的输入", value: $settings.value.searchMaxChars, in: 10...2000, step: 10)
                    .disabled(!settings.value.autoInSearch)
            } header: {
                Text("主搜索框")
            } footer: {
                Text("没有应用等强匹配时，译文排在第一行；有匹配时排在它们后面。回车复制译文，⌘↩ 粘贴到前台应用，⌥↩ 用译文替换输入。关闭后仍可用 translate 加空格触发。")
            }

            Section {
                ForEach(Array(settings.value.pairs.enumerated()), id: \.offset) { idx, _ in
                    HStack {
                        languagePicker(pairIndex: idx, side: .a)
                        Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                        languagePicker(pairIndex: idx, side: .b)
                        Spacer()
                        Button(role: .destructive) {
                            if settings.value.pairs.indices.contains(idx) { settings.value.pairs.remove(at: idx) }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("移除语言对")
                    }
                }
                HStack {
                    Button("添加语言对") { addPair() }
                    Button("恢复默认（中 ↔ 英）") { settings.value.pairs = [.chineseEnglish] }
                        .disabled(settings.value.pairs == [.chineseEnglish])
                }
            } header: {
                Text("语言")
            } footer: {
                Text("自动判断输入的语言：属于某个语言对中的一种，就翻译成另一种。同一种语言出现在多个语言对里时，主搜索框用靠前的，translate 关键词里会列出全部。")
            }

            Section {
                ForEach(Array(settings.value.orderedEngineIDs.enumerated()), id: \.element) { idx, id in
                    engineRow(id: id, index: idx, count: settings.value.orderedEngineIDs.count)
                }
                Menu("添加大模型…") {
                    ForEach(LLMPreset.all, id: \.name) { preset in
                        Button(preset.name) {
                            isNew = true
                            editing = LLMEngineConfig(name: preset.name, kind: preset.kind, baseURL: preset.baseURL, model: preset.model, requiresKey: preset.requiresKey)
                        }
                    }
                }
                Toggle("主搜索框自动翻译时也使用大模型", isOn: $settings.value.llmInSearch)
            } header: {
                Text("翻译引擎")
            } footer: {
                Text("按从上到下的顺序依次尝试，取第一个成功的结果。大模型会按调用量计费，默认只在 translate 关键词里使用；打开上面的开关后，主搜索框里每次输入也会调用。API Key 保存在系统钥匙串中。")
            }
        }
        .sheet(item: $editing) { cfg in
            LLMEngineEditor(config: cfg, isNew: isNew, context: context) { saved in
                if let i = settings.value.llmEngines.firstIndex(where: { $0.id == saved.id }) {
                    settings.value.llmEngines[i] = saved
                } else {
                    settings.value.llmEngines.append(saved)
                }
                editing = nil
            } onCancel: { editing = nil }
        }
    }

    // MARK: 语言对

    private enum Side { case a, b }

    private func languagePicker(pairIndex: Int, side: Side) -> some View {
        Picker("", selection: Binding(
            get: {
                guard settings.value.pairs.indices.contains(pairIndex) else { return "en" }
                return side == .a ? settings.value.pairs[pairIndex].a : settings.value.pairs[pairIndex].b
            },
            set: { new in
                guard settings.value.pairs.indices.contains(pairIndex) else { return }
                if side == .a { settings.value.pairs[pairIndex].a = new } else { settings.value.pairs[pairIndex].b = new }
            }
        )) {
            ForEach(TranslateLanguage.all) { Text($0.name).tag($0.code) }
        }
        .labelsHidden()
        .frame(width: 120)
    }

    private func addPair() {
        let existing = Set(settings.value.pairs.flatMap { [$0.a, $0.b] })
        let next = TranslateLanguage.all.first { !existing.contains($0.code) }?.code ?? "ja"
        settings.value.pairs.append(LanguagePair(a: "en", b: next))
    }

    // MARK: 引擎

    @ViewBuilder
    private func engineRow(id: String, index: Int, count: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            switch id {
            case EngineID.dictionary:
                DictionaryEngineRow(isOn: $settings.value.useDictionary)
            case EngineID.system:
                SystemEngineRow(isOn: $settings.value.useSystemTranslation, pairs: settings.value.pairs)
            default:
                if let cfg = settings.value.llmEngines.first(where: { $0.engineID == id }) {
                    llmRow(cfg)
                }
            }
            VStack(spacing: 0) {
                Button { move(id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(index == 0).accessibilityLabel("上移")
                Button { move(id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).disabled(index == count - 1).accessibilityLabel("下移")
            }
        }
    }

    private func llmRow(_ cfg: LLMEngineConfig) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cfg.name)
                Text("大模型 · \(cfg.kind.title) · \(cfg.model.isEmpty ? "未填写模型" : cfg.model)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("编辑…") { isNew = false; editing = cfg }
            Button(role: .destructive) {
                try? context.secrets.setSecret(nil, account: cfg.keyAccount)
                settings.value.llmEngines.removeAll { $0.id == cfg.id }
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).accessibilityLabel("删除大模型")
            Toggle("", isOn: Binding(
                get: { settings.value.llmEngines.first { $0.id == cfg.id }?.enabled ?? false },
                set: { on in
                    if let i = settings.value.llmEngines.firstIndex(where: { $0.id == cfg.id }) { settings.value.llmEngines[i].enabled = on }
                }
            ))
            .labelsHidden()
        }
    }

    private func move(_ id: String, by delta: Int) {
        var order = settings.value.orderedEngineIDs
        guard let i = order.firstIndex(of: id), order.indices.contains(i + delta) else { return }
        order.swapAt(i, i + delta)
        settings.value.engineOrder = order
    }
}

// MARK: - 词典

private struct DictionaryEngineRow: View {
    @Binding var isOn: Bool
    @State private var installed: Bool?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("牛津英汉汉英词典（系统词典）")
                Text(subtitle).font(.caption).foregroundStyle(installed == false ? .orange : .secondary)
            }
            Spacer()
            if installed == false {
                Button("打开词典 App") { openDictionaryApp() }
            }
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private var subtitle: String {
        switch installed {
        case nil: "检查中…"
        case true?: "已安装 · 仅处理中英单词和短语，离线、即时"
        case false?: "未安装 · 在“词典”App 的设置里勾选「简体中文 – 英文」，系统会自动下载牛津词典"
        }
    }

    private func refresh() async {
        SystemDictionary.shared.invalidateCache()
        installed = await Task.detached { SystemDictionary.shared.isInstalled() }.value
    }

    private func openDictionaryApp() {
        let url = URL(fileURLWithPath: "/System/Applications/Dictionary.app")
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 系统翻译

private struct SystemEngineRow: View {
    @Binding var isOn: Bool
    let pairs: [LanguagePair]
    @State private var status: [String: LanguageAvailability.Status] = [:]
    @State private var prepareConfig: TranslationSession.Configuration?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("系统翻译（离线）")
                Text(subtitle).font(.caption).foregroundStyle(missing.isEmpty ? Color.secondary : Color.orange)
            }
            Spacer()
            if !missing.isEmpty {
                Menu("下载语言包") {
                    ForEach(missing) { p in
                        Button("\(TranslateLanguage.name(of: p.a)) ↔ \(TranslateLanguage.name(of: p.b))") { prepare(p) }
                    }
                }
                .fixedSize()
            }
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .task(id: pairs) { await refresh() }
        .translationTask(prepareConfig) { @concurrent session in
            try? await session.prepareTranslation()
            await refresh()
        }
    }

    /// 已知支持但还没下载的语言对
    private var missing: [LanguagePair] {
        pairs.filter { status[$0.id] == .supported }
    }

    private var subtitle: String {
        if status.isEmpty { return "检查中…" }
        if !missing.isEmpty { return "有语言包未下载 · 点右侧按钮下载，或在 系统设置 › 通用 › 语言与地区 › 翻译语言 里下载" }
        let unsupported = pairs.filter { status[$0.id] == .unsupported }
        if !unsupported.isEmpty { return "不支持：" + unsupported.map { "\(TranslateLanguage.name(of: $0.a)) ↔ \(TranslateLanguage.name(of: $0.b))" }.joined(separator: "、") }
        return "语言包已就绪 · 适合句子和段落，离线运行"
    }

    private func refresh() async {
        var result: [String: LanguageAvailability.Status] = [:]
        let availability = LanguageAvailability()
        for p in pairs {
            result[p.id] = await availability.status(from: Locale.Language(identifier: p.a), to: Locale.Language(identifier: p.b))
        }
        status = result
    }

    private func prepare(_ p: LanguagePair) {
        let config = TranslationSession.Configuration(source: Locale.Language(identifier: p.a), target: Locale.Language(identifier: p.b))
        if prepareConfig == config { prepareConfig?.invalidate() } else { prepareConfig = config }
    }
}

// MARK: - 大模型编辑

struct LLMEngineEditor: View {
    @State var config: LLMEngineConfig
    let isNew: Bool
    let context: any PluginContext
    let onSave: (LLMEngineConfig) -> Void
    let onCancel: () -> Void
    @State private var apiKey = ""
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                TextField("名称", text: $config.name)
                Picker("协议", selection: $config.kind) {
                    ForEach(LLMKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Base URL", text: $config.baseURL).textContentType(.URL)
                SecureField(config.requiresKey ? "API Key" : "API Key（可选）", text: $apiKey)
                TextField("模型", text: $config.model)
                Text("API Key 保存在系统钥匙串中。").font(.caption).foregroundStyle(.secondary)
            }
            Section("附加提示词（可选）") {
                TextEditor(text: $config.extraPrompt).font(.system(size: 12)).frame(height: 60)
                    .scrollContentBackground(.hidden).padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                Text("例如“使用口语化的表达”“保留技术术语不翻译”。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("测试翻译") { Task { await test() } }.disabled(busy || config.baseURL.isEmpty || config.model.isEmpty)
                    if busy { ProgressView().controlSize(.small) }
                }
                if let s = status { Text(s).font(.caption).foregroundStyle(s.hasPrefix("✓") ? .green : .orange).textSelection(.enabled) }
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(config.name.isEmpty || config.baseURL.isEmpty || config.model.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
        .onAppear { apiKey = context.secrets.secret(config.keyAccount) ?? "" }
    }

    private func save() {
        try? context.secrets.setSecret(apiKey.isEmpty ? nil : apiKey, account: config.keyAccount)
        onSave(config)
    }

    private func test() async {
        busy = true; defer { busy = false }
        do {
            let out = try await LLMTranslator.translate(config, apiKey: apiKey, text: "Hello, world!", from: "en", to: "zh-Hans")
            status = "✓ Hello, world! → \(out)"
        } catch {
            status = error.localizedDescription
        }
    }
}
