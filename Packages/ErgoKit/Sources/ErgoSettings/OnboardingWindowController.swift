import AppKit
import KeyboardShortcuts
import SwiftUI
import ErgoCore
import ErgoPluginKit

@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let host: PluginHost
    private let services: CoreServices

    public init(host: PluginHost, services: CoreServices) {
        self.host = host
        self.services = services
    }

    public func show() {
        let view = OnboardingView(host: host, services: services) { [weak self] in self?.finish() }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = "欢迎使用 Ergo"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        let hc = NSHostingController(rootView: view)
        hc.sizingOptions = []
        w.contentViewController = hc
        w.setContentSize(NSSize(width: 560, height: 480))
        w.center()
        w.delegate = self
        window = w
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        services.appSettings.value.hasCompletedOnboarding = true
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        services.appSettings.value.hasCompletedOnboarding = true
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct OnboardingView: View {
    let host: PluginHost
    let services: CoreServices
    let done: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: permissions
                default: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
            Divider()
            HStack {
                if step > 0 { Button("上一步") { step -= 1 } }
                Spacer()
                if step < 2 {
                    Button("下一步") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("开始使用") { done() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("欢迎使用 Ergo").font(.largeTitle.bold())
            Text("一个由插件驱动的启动器。先设置唤起它的全局快捷键：")
                .foregroundStyle(.secondary)
            KeyboardShortcuts.Recorder("唤起 Ergo", name: .launcherToggle)
                .keyboardShortcutsConflictPolicy(.init(menuItem: .allow))
            Text("⌘Space 被“聚焦搜索”占用，如需使用请先在系统设置里关闭它。")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var permissions: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 12) {
                Text("授予权限").font(.title2.bold())
                Text("以下权限均为可选，只影响对应功能。").font(.callout).foregroundStyle(.secondary)
                ForEach([Permission.accessibility, .inputMonitoring, .pasteboard], id: \.self) { p in
                    PermissionRowView(
                        permission: p, status: services.permissions.status(p),
                        usedBy: host.registrations.filter { $0.manifest.permissions.contains { $0.permission == p } }.map(\.manifest.name),
                        services: services
                    )
                }
                Spacer()
            }
        }
    }

    private var finish: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("一切就绪").font(.largeTitle.bold())
            Text("按下快捷键唤起 Ergo。输入 app 名称、算式，或 cb、sn、ai、f 等关键词进入对应插件。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}
