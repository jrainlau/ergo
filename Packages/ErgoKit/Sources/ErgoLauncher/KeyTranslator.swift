import AppKit
import ErgoPluginKit

enum KeyTranslator {
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> ModifierSet {
        var m: ModifierSet = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.shift) { m.insert(.shift) }
        return m
    }

    static func press(from event: NSEvent) -> KeyStroke? {
        let mods = modifiers(event.modifierFlags)
        let key: LauncherKey
        switch event.keyCode {
        case 36, 76: key = .enter
        case 53: key = .escape
        case 48: key = .tab
        case 51: key = .deleteBackward
        case 126: key = .up
        case 125: key = .down
        case 123: key = .left
        case 124: key = .right
        case 116: key = .pageUp
        case 121: key = .pageDown
        default:
            // ⌘ + 数字：用 keyCode 映射，避免输入法 / 键盘布局影响
            let digitCodes: [UInt16: Character] = [18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9"]
            if let d = digitCodes[event.keyCode] {
                key = .character(d)
            } else if let ch = event.charactersIgnoringModifiers?.lowercased().first {
                key = .character(ch)
            } else {
                return nil
            }
        }
        return KeyStroke(key: key, modifiers: mods)
    }
}
