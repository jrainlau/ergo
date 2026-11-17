import KeyboardShortcuts
import SwiftUI
import ErgoCore
import ErgoPluginKit

struct PluginDetailView: View {
    let host: PluginHost
    @Bindable var registration: PluginRegistration
    let services: CoreServices
    let nav: SettingsNavigation
    @State private var showManagement = false

    var body: some View {
        Form {
            Section {
                Toggle("启用 \(registration.manifest.name)", isOn: Binding(
                    get: { registration.prefs.value.enabled },
                    set: { on in Task { await host.setEnabled(registration.id, on) } }
                ))
                switch registration.status {
                case .failed(let msg): Text("启动失败：\(msg)").font(.caption).foregroundStyle(.red)
                case .active: Text("运行中").font(.caption).foregroundStyle(.secondary)
                case .inactive: Text("未启用").font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text(registration.manifest.summary)
            }

            if !registration.manifest.keywords.isEmpty || !registration.prefs.value.keywords.isEmpty {
                keywordSection
            }
            if !registration.manifest.hotkeys.isEmpty {
                ForEach(registration.manifest.hotkeys, id: \.id) { action in
                    HotkeyActionSection(host: host, registration: registration, action: action, services: services)
                }
            }
            if !registration.manifest.permissions.isEmpty {
                Section("所需权限") {
                    ForEach(registration.manifest.permissions, id: \.permission) { req in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(req.permission.title + (req.isRequired ? "" : "（可选）"))
                                Text(req.reason).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            let s = services.permissions.status(req.permission)
                            Text(s == .granted ? "已授权" : "未授权").font(.caption).foregroundStyle(s == .granted ? .green : .orange)
                        }
                    }
                }
            }
            if registration.status == .active, let custom = registration.instance?.makeSettingsView() {
                custom
            }
            if registration.status == .active, registration.instance?.makeManagementView() != nil {
                Section {
                    Button("打开管理…") { showManagement = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(registration.manifest.name)
        .task { consumePendingManagement() }
        .onChange(of: nav.pendingManagement) { _, _ in consumePendingManagement() }
        .sheet(isPresented: $showManagement) {
            VStack(spacing: 0) {
                registration.instance?.makeManagementView()
                Divider()
                HStack { Spacer(); Button("完成") { showManagement = false }.keyboardShortcut(.defaultAction) }.padding(12)
            }
            .frame(minWidth: 800, minHeight: 560)
        }
    }

    private func consumePendingManagement() {
        if nav.pendingManagement == registration.id, registration.status == .active {
            nav.pendingManagement = nil
            showManagement = true
        }
    }

    private var keywordSection: some View {
        Section {
            ForEach(Array(registration.prefs.value.keywords.enumerated()), id: \.offset) { idx, _ in
                HStack {
                    TextField("关键词", text: Binding(
                        get: { registration.prefs.value.keywords.indices.contains(idx) ? registration.prefs.value.keywords[idx].text : "" },
                        set: { if registration.prefs.value.keywords.indices.contains(idx) { registration.prefs.value.keywords[idx].text = $0 } }
                    ))
                    Button(role: .destructive) {
                        registration.prefs.value.keywords.remove(at: idx)
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删除关键词")
                }
            }
            Button("添加关键词") {
                registration.prefs.value.keywords.append(KeywordTrigger(text: ""))
            }
        } header: {
            Text("唤起关键词")
        } footer: {
            let conflicts = host.keywordConflicts
            if conflicts.isEmpty {
                Text("在输入框中输入关键词加空格即可进入该插件。")
            } else {
                Text("关键词冲突：\(conflicts.joined(separator: "、"))，后注册的插件不会生效。").foregroundStyle(.orange)
            }
        }
    }
}

private enum ModeKind: Hashable { case none, combo, doubleTap }

struct HotkeyActionSection: View {
    let host: PluginHost
    @Bindable var registration: PluginRegistration
    let action: HotkeyActionDescriptor
    let services: CoreServices

    private var mode: HotkeyMode { registration.mode(for: action) }

    private var kind: Binding<ModeKind> {
        Binding(
            get: {
                switch mode {
                case .none: .none
                case .combo: .combo
                case .doubleTap: .doubleTap
                }
            },
            set: { k in
                switch k {
                case .none: registration.setMode(.none, for: action)
                case .combo: registration.setMode(.combo, for: action)
                case .doubleTap:
                    if case .doubleTap = mode {} else { registration.setMode(.doubleTap(.control), for: action) }
                }
                host.onChange()
            }
        )
    }

    var body: some View {
        Section {
            Picker("触发方式", selection: kind) {
                Text("无").tag(ModeKind.none)
                Text("组合键").tag(ModeKind.combo)
                Text("双击修饰键").tag(ModeKind.doubleTap)
            }
            switch mode {
            case .combo:
                KeyboardShortcuts.Recorder("快捷键", name: HotkeyService.name(plugin: registration.id, action: action)) { _ in
                    host.onChange()
                }
                .keyboardShortcutsConflictPolicy(.init(menuItem: .allow))
            case .doubleTap(let key):
                Picker("修饰键", selection: Binding(
                    get: { key },
                    set: { registration.setMode(.doubleTap($0), for: action); host.onChange() }
                )) {
                    ForEach(ModifierKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if services.permissions.status(.inputMonitoring) != .granted {
                    Text("双击修饰键需要“输入监控”权限，请到“权限”页授权后重启 Ergo。")
                        .font(.caption).foregroundStyle(.orange)
                }
            case .none:
                EmptyView()
            }
        } header: {
            Text(action.title)
        }
    }
}
