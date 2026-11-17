import Foundation
import ErgoPluginKit

public nonisolated enum HotkeyMode: Codable, Equatable, Hashable, Sendable {
    case none
    case combo
    case doubleTap(ModifierKey)
}

public nonisolated struct PluginPreferences: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var keywords: [KeywordTrigger]
    public var hotkeyModes: [String: HotkeyMode]

    public init(enabled: Bool, keywords: [KeywordTrigger], hotkeyModes: [String: HotkeyMode]) {
        self.enabled = enabled
        self.keywords = keywords
        self.hotkeyModes = hotkeyModes
    }

    public static func defaults(for manifest: PluginManifest) -> PluginPreferences {
        var modes: [String: HotkeyMode] = [:]
        for h in manifest.hotkeys {
            switch h.defaultTrigger {
            case .none: modes[h.id.rawValue] = HotkeyMode.none
            case .combo: modes[h.id.rawValue] = .combo
            case .doubleTap(let k): modes[h.id.rawValue] = .doubleTap(k)
            }
        }
        return PluginPreferences(enabled: manifest.enabledByDefault, keywords: manifest.keywords, hotkeyModes: modes)
    }
}
