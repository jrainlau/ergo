import Foundation

public struct ModifierSet: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let control = ModifierSet(rawValue: 1 << 2)
    public static let shift = ModifierSet(rawValue: 1 << 3)
}

public enum ModifierKey: String, Sendable, Codable, CaseIterable, Hashable {
    case control, option, command, shift

    public var title: String {
        switch self {
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        case .shift: "Shift"
        }
    }
}

/// keyCode 为 Carbon kVK 虚拟键码。
public struct KeyCombo: Sendable, Codable, Hashable {
    public var keyCode: UInt16
    public var modifiers: ModifierSet
    public init(keyCode: UInt16, modifiers: ModifierSet) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum HotkeyTrigger: Sendable, Codable, Hashable {
    case none
    case combo(KeyCombo)
    case doubleTap(ModifierKey)
}

public enum LauncherKey: Hashable, Sendable {
    case up, down, left, right, enter, tab, escape, deleteBackward, pageUp, pageDown
    case character(Character)
}

public struct KeyPress: Hashable, Sendable {
    public var key: LauncherKey
    public var modifiers: ModifierSet
    public init(key: LauncherKey, modifiers: ModifierSet = []) {
        self.key = key
        self.modifiers = modifiers
    }
}
