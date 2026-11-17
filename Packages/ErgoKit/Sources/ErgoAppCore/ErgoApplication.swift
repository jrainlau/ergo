import AppKit
import ErgoCore
import ErgoLauncher
import ErgoPluginKit
import ErgoSettings
import OSLog

@MainActor
public enum ErgoApplication {
    private static var delegate: AppDelegate?

    public static func run() {
        let app = NSApplication.shared
        let d = AppDelegate()
        delegate = d
        app.delegate = d
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: CoreServices!
    private var host: PluginHost!
    private var launcher: LauncherWindowController!
    private var hotkeys: HotkeyService!
    private var statusItem: StatusItemController!
    private var settingsController: SettingsWindowController!
    private var onboarding: OnboardingWindowController?
    private var lastDoubleTapInterval: Double = -1
    private let log = Logger(subsystem: ErgoPaths.bundleID, category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        services = CoreServices()
        NSApp.mainMenu = MainMenuBuilder.build(openSettings: #selector(openSettings), target: self)

        host = PluginHost(types: PluginCatalog.all, services: services)
        launcher = LauncherWindowController(host: host, services: services)
        launcher.onOpenSettings = { [weak self] in self?.openSettings() }

        settingsController = SettingsWindowController(host: host, services: services)
        settingsController.onResetPlacement = { [weak self] in self?.launcher.resetPlacement() }

        services.launcher.onOpenSettings = { [weak self] id, management in
            self?.launcher.hide()
            self?.settingsController.show(page: .plugin(id), openManagement: management)
        }

        hotkeys = HotkeyService(host: host, settings: services.appSettings)
        hotkeys.registerMain { [weak self] in self?.launcher.toggle() }
        host.onChange = { [weak self] in self?.hotkeys.syncPluginHotkeys() }

        statusItem = StatusItemController(host: host, services: services)
        statusItem.onOpenLauncher = { [weak self] in self?.launcher.show(scope: nil, query: nil) }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItem.onOpenScope = { [weak self] id in self?.launcher.show(scope: id, query: nil) }

        applySettings()
        observeContinuously(
            track: { [weak self] in _ = self?.services.appSettings.value },
            perform: { [weak self] in self?.applySettings() }
        )

        #if DEBUG
        installDebugHook()
        #endif

        Task {
            await host.startAll()
            log.info("plugins started: \(self.host.activeRegistrations.count)/\(self.host.registrations.count)")
        }

        if !services.appSettings.value.hasCompletedOnboarding {
            onboarding = OnboardingWindowController(host: host, services: services)
            onboarding?.show()
        }
    }

    #if DEBUG
    /// 仅调试构建：通过分布式通知驱动启动器，便于自动化验证。
    /// userInfo: action = show|hide|query|key|settings, scope, query, key
    private func installDebugHook() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.jrainlau.ergo.debug"), object: nil, queue: .main
        ) { [weak self] note in
            let info = note.userInfo ?? [:]
            let action = info["action"] as? String
            let scopeName = info["scope"] as? String
            let queryText = info["query"] as? String
            let keyName = (info["key"] as? String) ?? ""
            let cmd = (info["mods"] as? String) == "cmd"
            MainActor.assumeIsolated {
                guard let self else { return }
                switch action {
                case "show":
                    self.launcher.show(scope: scopeName.map { PluginID($0) }, query: queryText)
                case "hide": self.launcher.hide()
                case "query": self.launcher.model.query = queryText ?? ""
                case "settings": self.settingsController.show()
                case "key":
                    let name = keyName
                    let mods: ModifierSet = cmd ? .command : []
                    let key: LauncherKey? = switch name {
                    case "enter": .enter
                    case "down": .down
                    case "up": .up
                    case "esc": .escape
                    case "left": .left
                    case "right": .right
                    default: name.first.map { .character($0) }
                    }
                    if let key { _ = self.launcher.model.handle(KeyStroke(key: key, modifiers: mods)) }
                default: break
                }
            }
        }
    }
    #endif

    private func applySettings() {
        let s = services.appSettings.value
        switch s.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        statusItem.setVisible(s.showMenuBarIcon)
        if lastDoubleTapInterval != s.doubleTapInterval {
            lastDoubleTapInterval = s.doubleTapInterval
            hotkeys.syncPluginHotkeys()
        }
    }

    @objc func openSettings() {
        launcher.hide()
        settingsController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }
}
