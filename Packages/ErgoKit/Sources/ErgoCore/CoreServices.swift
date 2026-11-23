import Foundation
import ErgoPluginKit

/// 宿主服务集合，由组合根创建并传给 PluginHost / Launcher / Settings。
public final class CoreServices {
    public let settingsStore: SettingsStore
    public let appSettings: AppSettings
    public let secrets: SecretStore
    public let usage: UsageStore
    public let permissions: PermissionService
    public let hud: HUDService
    public let icons: IconProvider
    public let frontApp: FrontAppTracker
    public let paste: PasteService
    public let launcher: LauncherBridge
    public let updateSettings: SettingsBox<UpdateSettingsData>
    public let updates: UpdateBridge

    public init(defaults: UserDefaults = .standard, databaseURL: URL? = ErgoPaths.databaseURL, keychainService: String = ErgoPaths.bundleID) {
        let store = SettingsStore(defaults: defaults)
        settingsStore = store
        appSettings = AppSettings(store: store, key: "ergo.app.settings", default: AppSettingsData())
        secrets = SecretStore(service: keychainService)
        usage = UsageStore(url: databaseURL)
        permissions = PermissionService()
        hud = HUDService()
        icons = IconProvider()
        frontApp = FrontAppTracker()
        paste = PasteService(frontApp: frontApp, hud: hud)
        launcher = LauncherBridge()
        updateSettings = SettingsBox(store: store, key: "ergo.update.settings", default: UpdateSettingsData())
        updates = UpdateBridge()
    }
}
