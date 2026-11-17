import Foundation
import Observation
import OSLog
import SwiftUI
import ErgoPluginKit

@MainActor
final class PluginContextImpl: PluginContext {
    let pluginID: PluginID
    let dataDirectory: URL
    let cacheDirectory: URL
    let logger: Logger
    let settings: any SettingsStoring
    let secrets: any SecretStoring
    let launcher: any LauncherControlling
    let pasteboard: any PasteServicing
    let permissions: any PermissionServicing
    let hud: any HUDPresenting
    let usage: any UsageRecording
    let icons: any IconProviding
    let frontApp: any FrontAppProviding

    init(id: PluginID, services: CoreServices) {
        pluginID = id
        dataDirectory = ErgoPaths.pluginData(id)
        cacheDirectory = ErgoPaths.pluginCache(id)
        logger = Logger(subsystem: ErgoPaths.bundleID, category: id.rawValue)
        settings = services.settingsStore.scoped("ergo.plugin.\(id.rawValue).settings.")
        secrets = services.secrets
        launcher = services.launcher
        pasteboard = services.paste
        permissions = services.permissions
        hud = services.hud
        usage = services.usage
        icons = services.icons
        frontApp = services.frontApp
    }
}

public enum PluginStatus: Equatable {
    case inactive
    case active
    case failed(String)
}

@MainActor
@Observable
public final class PluginRegistration: Identifiable {
    public let manifest: PluginManifest
    let type: any ErgoPlugin.Type
    public internal(set) var instance: (any ErgoPlugin)?
    public internal(set) var status: PluginStatus = .inactive
    public let prefs: SettingsBox<PluginPreferences>

    public nonisolated var id: PluginID { manifest.id }

    init(type: any ErgoPlugin.Type, store: SettingsStore) {
        self.type = type
        self.manifest = type.manifest
        self.prefs = SettingsBox(
            store: store,
            key: "ergo.plugin.\(type.manifest.id.rawValue).prefs",
            default: PluginPreferences.defaults(for: type.manifest)
        )
    }

    public func mode(for action: HotkeyActionDescriptor) -> HotkeyMode {
        if let m = prefs.value.hotkeyModes[action.id.rawValue] { return m }
        return PluginPreferences.defaults(for: manifest).hotkeyModes[action.id.rawValue] ?? .none
    }

    public func setMode(_ mode: HotkeyMode, for action: HotkeyActionDescriptor) {
        prefs.value.hotkeyModes[action.id.rawValue] = mode
    }
}

public struct KeywordMatch {
    public let registration: PluginRegistration
    public let keyword: KeywordTrigger
    public let remainder: String
}

@MainActor
@Observable
public final class PluginHost {
    public private(set) var registrations: [PluginRegistration] = []
    /// 插件启用状态、快捷键配置变化时触发
    @ObservationIgnored public var onChange: () -> Void = {}
    @ObservationIgnored private let services: CoreServices

    public init(types: [any ErgoPlugin.Type], services: CoreServices) {
        self.services = services
        self.registrations = types.map { PluginRegistration(type: $0, store: services.settingsStore) }
    }

    public func registration(for id: PluginID) -> PluginRegistration? {
        registrations.first { $0.id == id }
    }

    public var activeRegistrations: [PluginRegistration] {
        registrations.filter { $0.status == .active }
    }

    public func startAll() async {
        for reg in registrations where reg.prefs.value.enabled {
            await activate(reg)
        }
        onChange()
    }

    private func activate(_ reg: PluginRegistration) async {
        let plugin = reg.type.init()
        let ctx = PluginContextImpl(id: reg.id, services: services)
        do {
            try await plugin.activate(context: ctx)
            reg.instance = plugin
            reg.status = .active
        } catch {
            reg.instance = nil
            reg.status = .failed(error.localizedDescription)
            ctx.logger.error("activate failed: \(error.localizedDescription)")
        }
    }

    private func deactivate(_ reg: PluginRegistration) async {
        await reg.instance?.deactivate()
        reg.instance = nil
        reg.status = .inactive
    }

    public func setEnabled(_ id: PluginID, _ enabled: Bool) async {
        guard let reg = registration(for: id) else { return }
        reg.prefs.value.enabled = enabled
        if enabled { await activate(reg) } else { await deactivate(reg) }
        onChange()
    }

    // MARK: - 关键词

    /// 关键词冲突（后注册的不生效）。
    public var keywordConflicts: [String] {
        var seen = Set<String>()
        var conflicts: [String] = []
        for reg in activeRegistrations {
            for k in reg.prefs.value.keywords {
                let key = k.text.lowercased()
                if !seen.insert(key).inserted { conflicts.append(key) }
            }
        }
        return conflicts
    }

    public func matchKeyword(_ raw: String) -> KeywordMatch? {
        let lower = raw.lowercased()
        var best: KeywordMatch?
        for reg in activeRegistrations {
            for k in reg.prefs.value.keywords where !k.text.isEmpty {
                let kw = k.text.lowercased()
                let needle = k.requiresSpace ? kw + " " : kw
                guard lower.hasPrefix(needle) else { continue }
                let rest = String(raw.dropFirst(needle.count))
                if best == nil || kw.count > best!.keyword.text.count {
                    best = KeywordMatch(registration: reg, keyword: k, remainder: rest)
                }
            }
        }
        return best
    }

    public func makeScope(for id: PluginID) -> (any PluginScope)? {
        registration(for: id)?.instance?.makeScope()
    }

    public func runHotkey(plugin id: PluginID, action: HotkeyActionID) {
        guard let p = registration(for: id)?.instance else { return }
        Task { await p.perform(hotkey: action) }
    }
}
