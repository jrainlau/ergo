import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import ErgoPluginKit

public extension KeyboardShortcuts.Name {
    static let launcherToggle = Self("ergo.launcher.toggle", initial: .init(.space, modifiers: [.option]))
}

public final class HotkeyService {
    private let host: PluginHost
    private let settings: AppSettings
    private let monitor = ModifierTapMonitor()

    public init(host: PluginHost, settings: AppSettings) {
        self.host = host
        self.settings = settings
    }

    public var isDoubleTapAvailable: Bool { CGPreflightListenEventAccess() }

    public func registerMain(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.removeHandler(for: .launcherToggle)
        KeyboardShortcuts.onKeyDown(for: .launcherToggle) { Task { @MainActor in handler() } }
    }

    public static func name(plugin: PluginID, action: HotkeyActionDescriptor) -> KeyboardShortcuts.Name {
        var def: KeyboardShortcuts.Shortcut?
        if case .combo(let c) = action.defaultTrigger {
            def = .init(carbonKeyCode: Int(c.keyCode), carbonModifiers: carbonModifiers(c.modifiers))
        }
        return KeyboardShortcuts.Name("plugin.\(plugin.rawValue).\(action.id.rawValue)", initial: def)
    }

    static func carbonModifiers(_ m: ModifierSet) -> Int {
        var r = 0
        if m.contains(.command) { r |= cmdKey }
        if m.contains(.shift) { r |= shiftKey }
        if m.contains(.option) { r |= optionKey }
        if m.contains(.control) { r |= controlKey }
        return r
    }

    /// 根据插件状态与偏好，重新注册所有插件快捷键。
    public func syncPluginHotkeys() {
        var taps: [ModifierKey: [() -> Void]] = [:]
        for reg in host.registrations {
            for action in reg.manifest.hotkeys {
                let name = Self.name(plugin: reg.id, action: action)
                KeyboardShortcuts.removeHandler(for: name)
                let active = reg.status == .active
                switch reg.mode(for: action) {
                case .combo where active:
                    KeyboardShortcuts.enable(name)
                    let pid = reg.id, aid = action.id
                    KeyboardShortcuts.onKeyDown(for: name) { [host] in
                        Task { @MainActor in host.runHotkey(plugin: pid, action: aid) }
                    }
                case .doubleTap(let key) where active:
                    KeyboardShortcuts.disable(name)
                    let pid = reg.id, aid = action.id
                    taps[key, default: []].append { [host] in host.runHotkey(plugin: pid, action: aid) }
                default:
                    KeyboardShortcuts.disable(name)
                }
            }
        }
        monitor.setBindings(taps, interval: settings.value.doubleTapInterval)
    }
}
