import SwiftUI
import ErgoPluginKit

struct AISettingsView: View {
    @Bindable var settings: SettingsBox<AIChatSettings>
    let context: any PluginContext
    @State private var editing: AIProviderConfig?
    @State private var isNew = false

    var body: some View {
        Group {
            Section("提供商") {
                if settings.value.providers.isEmpty {
                    Text("尚未配置").foregroundStyle(.secondary)
                }
                ForEach(settings.value.providers) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                Text(p.name)
                                if settings.value.defaultProviderID == p.id || (settings.value.defaultProviderID == nil && p.id == settings.value.providers.first?.id) {
                                    Text("默认").font(.caption2).padding(.horizontal, 5).background(Capsule().fill(Color.accentColor.opacity(0.2)))
                                }
                            }
                            Text("\(p.kind.title) · \(p.defaultModel.isEmpty ? "未选择模型" : p.defaultModel)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("设为默认") { settings.value.defaultProviderID = p.id }.buttonStyle(.borderless)
                        Button("编辑…") { isNew = false; editing = p }
                        Button(role: .destructive) {
                            try? context.secrets.setSecret(nil, account: p.keyAccount)
                            settings.value.providers.removeAll { $0.id == p.id }
                            if settings.value.defaultProviderID == p.id { settings.value.defaultProviderID = nil }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("删除提供商")
                    }
                }
                Menu("添加提供商") {
                    ForEach(AIPreset.all, id: \.name) { preset in
                        Button(preset.name) {
                            isNew = true
                            editing = AIProviderConfig(name: preset.name == "自定义" ? "自定义" : preset.name, kind: preset.kind, baseURL: preset.baseURL, requiresKey: preset.requiresKey)
                        }
                    }
                }
            }
            Section("对话") {
                VStack(alignment: .leading) {
                    Text("系统提示词")
                    TextEditor(text: $settings.value.systemPrompt).font(.system(size: 12)).frame(height: 70)
                        .scrollContentBackground(.hidden).padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                }
                LabeledContent(String(format: "Temperature %.1f", settings.value.temperature)) {
                    Slider(value: $settings.value.temperature, in: 0...1.5, step: 0.1).frame(width: 200)
                }
                Stepper("携带最近 \(settings.value.contextMessages) 条消息", value: $settings.value.contextMessages, in: 2...100, step: 2)
                Stepper("\(settings.value.resumeMinutes) 分钟内再次打开时继续上一个会话", value: $settings.value.resumeMinutes, in: 1...720, step: 5)
            }
        }
        .sheet(item: $editing) { cfg in
            AIProviderEditor(config: cfg, isNew: isNew, context: context) { saved in
                if let i = settings.value.providers.firstIndex(where: { $0.id == saved.id }) {
                    settings.value.providers[i] = saved
                } else {
                    settings.value.providers.append(saved)
                    if settings.value.defaultProviderID == nil { settings.value.defaultProviderID = saved.id }
                }
                editing = nil
            } onCancel: { editing = nil }
        }
    }
}

struct AIProviderEditor: View {
    @State var config: AIProviderConfig
    let isNew: Bool
    let context: any PluginContext
    let onSave: (AIProviderConfig) -> Void
    let onCancel: () -> Void
    @State private var apiKey = ""
    @State private var modelsText = ""
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                TextField("名称", text: $config.name)
                Picker("协议", selection: $config.kind) {
                    ForEach(AIProviderKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Base URL", text: $config.baseURL).textContentType(.URL)
                SecureField(config.requiresKey ? "API Key" : "API Key（可选）", text: $apiKey)
                Text("API Key 保存在系统钥匙串中。").font(.caption).foregroundStyle(.secondary)
            }
            Section("模型") {
                TextEditor(text: $modelsText).font(.system(size: 12, design: .monospaced)).frame(height: 80)
                    .scrollContentBackground(.hidden).padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                Text("每行一个模型名；可点击“获取模型列表”自动填充。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("获取模型列表") { Task { await fetchModels() } }.disabled(busy || config.baseURL.isEmpty)
                    Button("测试连接") { Task { await testConnection() } }.disabled(busy || config.baseURL.isEmpty)
                    if busy { ProgressView().controlSize(.small) }
                }
                if let s = status { Text(s).font(.caption).foregroundStyle(s.hasPrefix("✓") ? .green : .orange).textSelection(.enabled) }
                let models = parsedModels
                Picker("默认模型", selection: $config.defaultModel) {
                    Text("未选择").tag("")
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                    if !config.defaultModel.isEmpty, !models.contains(config.defaultModel) { Text(config.defaultModel).tag(config.defaultModel) }
                }
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(config.name.isEmpty || config.baseURL.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear {
            apiKey = context.secrets.secret(config.keyAccount) ?? ""
            modelsText = config.models.joined(separator: "\n")
        }
    }

    private var parsedModels: [String] {
        modelsText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() {
        var c = config
        c.models = parsedModels
        if c.defaultModel.isEmpty { c.defaultModel = c.models.first ?? "" }
        try? context.secrets.setSecret(apiKey.isEmpty ? nil : apiKey, account: c.keyAccount)
        onSave(c)
    }

    private func fetchModels() async {
        busy = true; defer { busy = false }
        do {
            let list = try await ModelLister.fetch(kind: config.kind, baseURL: config.baseURL, apiKey: apiKey, extraHeaders: config.extraHeaders)
            modelsText = list.joined(separator: "\n")
            if config.defaultModel.isEmpty { config.defaultModel = list.first ?? "" }
            status = "✓ 获取到 \(list.count) 个模型"
        } catch { status = error.localizedDescription }
    }

    private func testConnection() async {
        busy = true; defer { busy = false }
        do {
            let list = try await ModelLister.fetch(kind: config.kind, baseURL: config.baseURL, apiKey: apiKey, extraHeaders: config.extraHeaders)
            status = "✓ 连接成功（\(list.count) 个模型）"
        } catch { status = error.localizedDescription }
    }
}
