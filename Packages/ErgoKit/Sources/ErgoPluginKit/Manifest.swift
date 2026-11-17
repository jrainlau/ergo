import Foundation

public struct KeywordTrigger: Sendable, Codable, Hashable {
    public var text: String
    public var requiresSpace: Bool
    public init(text: String, requiresSpace: Bool = true) {
        self.text = text
        self.requiresSpace = requiresSpace
    }
}

public struct HotkeyActionDescriptor: Sendable {
    public var id: HotkeyActionID
    public var title: String
    public var defaultTrigger: HotkeyTrigger
    public init(id: HotkeyActionID, title: String, defaultTrigger: HotkeyTrigger = .none) {
        self.id = id
        self.title = title
        self.defaultTrigger = defaultTrigger
    }
}

public struct PluginManifest: Sendable {
    public var id: PluginID
    public var name: String
    public var summary: String
    public var symbolName: String
    public var version: String
    public var permissions: [PermissionRequirement]
    public var keywords: [KeywordTrigger]
    public var hotkeys: [HotkeyActionDescriptor]
    public var enabledByDefault: Bool

    public init(
        id: PluginID,
        name: String,
        summary: String,
        symbolName: String,
        version: String = "1.0.0",
        permissions: [PermissionRequirement] = [],
        keywords: [KeywordTrigger] = [],
        hotkeys: [HotkeyActionDescriptor] = [],
        enabledByDefault: Bool = true
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbolName = symbolName
        self.version = version
        self.permissions = permissions
        self.keywords = keywords
        self.hotkeys = hotkeys
        self.enabledByDefault = enabledByDefault
    }
}
