import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import ErgoCore
import ErgoPluginKit

struct GeneralPage: View {
    @Bindable var settings: AppSettings
    let resetPlacement: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("启动") {
                Toggle("开机自动启动", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                ))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("在菜单栏显示图标", isOn: $settings.value.showMenuBarIcon)
            }
            Section {
                KeyboardShortcuts.Recorder("唤起 Ergo", name: .launcherToggle)
                    .keyboardShortcutsConflictPolicy(.init(menuItem: .allow))
            } header: {
                Text("快捷键")
            } footer: {
                Text("⌘Space 默认被“聚焦搜索”占用。如需使用，请先到 系统设置 › 键盘 › 键盘快捷键 › 聚焦 中关闭它。")
            }
            Section("行为") {
                Picker("显示在", selection: $settings.value.showOnScreen) {
                    ForEach(ScreenChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("失去焦点时自动隐藏", isOn: $settings.value.hideOnResignKey)
                Toggle("保留上次输入", isOn: $settings.value.keepLastQuery)
                Stepper("最多显示 \(settings.value.maxVisibleRows) 行结果", value: $settings.value.maxVisibleRows, in: 5...12)
                LabeledContent("窗口宽度 \(Int(settings.value.panelWidth))") {
                    Slider(value: $settings.value.panelWidth, in: 600...900, step: 10)
                        .frame(width: 220)
                }
                Button("重置窗口位置", action: resetPlacement)
            }
            Section {
                LabeledContent(String(format: "双击间隔 %.2f 秒", settings.value.doubleTapInterval)) {
                    Slider(value: $settings.value.doubleTapInterval, in: 0.2...0.5, step: 0.05)
                        .frame(width: 220)
                }
            } header: {
                Text("双击修饰键")
            } footer: {
                Text("用于“连按两次 Control”这类快捷键，需要“输入监控”权限。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("通用")
    }
}

struct AppearancePage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("启动器面板") {
                Picker("材质", selection: $settings.value.material) {
                    ForEach(PanelMaterial.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("外观", selection: $settings.value.appearance) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("外观")
    }
}

struct AboutPage: View {
    @Bindable var settings: SettingsBox<UpdateSettingsData>
    let updates: UpdateBridge

    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        Form {
            Section {
                LabeledContent("版本", value: version)
                LabeledContent("数据目录") {
                    Button("在访达中打开") { NSWorkspace.shared.open(ErgoPaths.appSupport) }
                }
            }
            Section {
                Toggle("自动检查更新", isOn: $settings.value.autoCheck)
                Toggle("包含预发布版本", isOn: $settings.value.includePrereleases)
                LabeledContent {
                    Button("检查更新") { updates.onCheckNow() }
                        .disabled(updates.isBusy)
                } label: {
                    Text(updates.status.isEmpty ? "每 6 小时检查一次 GitHub Releases" : updates.status)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("更新")
            } footer: {
                Text("发现新版本后会先下载并校验，经你确认后自动替换并重启。")
            }
            Section("排查问题") {
                Text("在终端中运行以下命令查看实时日志：")
                Text("log stream --predicate 'subsystem == \"com.jrainlau.ergo\"' --level debug")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("关于")
    }
}
