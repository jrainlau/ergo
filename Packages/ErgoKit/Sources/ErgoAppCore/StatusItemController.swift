import AppKit
import ErgoCore
import ErgoPluginKit
import KeyboardShortcuts

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let host: PluginHost
    private let services: CoreServices
    var onOpenLauncher: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onOpenScope: (PluginID) -> Void = { _ in }

    init(host: PluginHost, services: CoreServices) {
        self.host = host
        self.services = services
    }

    private static func menuBarImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "command.square", accessibilityDescription: "Ergo")
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Ergo"
        return image
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            i.button?.image = Self.menuBarImage()
            let menu = NSMenu()
            menu.delegate = self
            i.menu = menu
            item = i
        } else if !visible, let i = item {
            NSStatusBar.system.removeStatusItem(i)
            item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    /// 构建与菜单栏相同的菜单，供启动器右上角右键入口复用。
    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        let open = NSMenuItem(title: "打开 Ergo", action: #selector(openLauncher), keyEquivalent: "")
        open.target = self
        if let sc = KeyboardShortcuts.getShortcut(for: .launcherToggle) {
            open.title = "打开 Ergo（\(sc)）"
        }
        menu.addItem(open)

        if host.registration(for: "ergo.clipboard")?.status == .active {
            let cb = NSMenuItem(title: "剪贴板历史", action: #selector(openClipboard), keyEquivalent: "")
            cb.target = self
            menu.addItem(cb)
        }
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        var missing: [String] = []
        for p in [Permission.accessibility, .inputMonitoring] where services.permissions.status(p) != .granted {
            missing.append(p.title)
        }
        if !missing.isEmpty {
            let w = NSMenuItem(title: "⚠︎ 缺少权限：" + missing.joined(separator: "、"), action: #selector(openSettings), keyEquivalent: "")
            w.target = self
            menu.addItem(w)
        }

        let data = NSMenuItem(title: "打开数据目录", action: #selector(openData), keyEquivalent: "")
        data.target = self
        menu.addItem(data)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Ergo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openLauncher() { onOpenLauncher() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func openClipboard() { onOpenScope("ergo.clipboard") }
    @objc private func openData() { NSWorkspace.shared.open(ErgoPaths.appSupport) }
}
