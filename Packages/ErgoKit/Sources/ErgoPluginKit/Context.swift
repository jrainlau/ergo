import AppKit
import Observation
import OSLog

@MainActor
public protocol SettingsStoring: AnyObject {
    func load<T: Codable>(_ type: T.Type, key: String) -> T?
    func save<T: Codable>(_ value: T, key: String)
}

@MainActor
public protocol SecretStoring: AnyObject {
    func secret(_ account: String) -> String?
    func setSecret(_ value: String?, account: String) throws
}

@MainActor
public protocol HUDPresenting: AnyObject {
    func show(_ text: String, symbol: String?)
}

@MainActor
public protocol UsageRecording: AnyObject {
    func record(itemID: String, query: String)
    /// 0...0.2，同步读内存缓存
    func boost(itemID: String, query: String) -> Double
}

@MainActor
public protocol IconProviding: AnyObject {
    func icon(for url: URL, size: CGFloat) -> NSImage
}

@MainActor
public protocol FrontAppProviding: AnyObject {
    var previousApplication: NSRunningApplication? { get }
}

@MainActor
public protocol PermissionServicing: AnyObject {
    func status(_ permission: Permission) -> PermissionStatus
    func request(_ permission: Permission)
    func openSystemSettings(for permission: Permission)
}

public enum PasteContent {
    case text(String)
    case richText(rtf: Data, plain: String)
    case image(png: Data)
    case fileURLs([URL])
    case url(URL)
    case color(NSColor)
}

public enum PasteResult {
    case pasted
    case copiedOnly(reason: String)
}

@MainActor
public protocol PasteServicing: AnyObject {
    func copy(_ content: PasteContent, marker: String?)
    func paste(_ content: PasteContent, marker: String?, restoreClipboard: Bool) async -> PasteResult
    func postKeystrokes(leftArrowCount: Int) async
}

@MainActor
public protocol LauncherControlling: AnyObject {
    var isVisible: Bool { get }
    func show(scope: PluginID?, query: String?)
    func hide()
    func setQuery(_ text: String)
    func refresh()
}

@MainActor
public protocol PluginContext: AnyObject {
    var pluginID: PluginID { get }
    var dataDirectory: URL { get }
    var cacheDirectory: URL { get }
    var logger: Logger { get }
    var settings: any SettingsStoring { get }
    var secrets: any SecretStoring { get }
    var launcher: any LauncherControlling { get }
    var pasteboard: any PasteServicing { get }
    var permissions: any PermissionServicing { get }
    var hud: any HUDPresenting { get }
    var usage: any UsageRecording { get }
    var icons: any IconProviding { get }
    var frontApp: any FrontAppProviding { get }
}

/// 插件设置容器：value 变化时自动落盘。
@MainActor
@Observable
public final class SettingsBox<T: Codable & Equatable> {
    public var value: T {
        didSet {
            if value != oldValue { store.save(value, key: key) }
        }
    }
    @ObservationIgnored private let store: any SettingsStoring
    @ObservationIgnored private let key: String

    public init(store: any SettingsStoring, key: String, default defaultValue: T) {
        self.store = store
        self.key = key
        self.value = store.load(T.self, key: key) ?? defaultValue
    }
}
