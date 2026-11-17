import Foundation
import ErgoPluginKit

/// 双击修饰键检测状态机（纯逻辑，可单测）。
public nonisolated struct DoubleTapDetector: Sendable {
    public enum Event: Sendable {
        /// keyCode 为触发事件的键，flags 为事件之后仍按下的修饰键集合
        case flagsChanged(keyCode: UInt16, flags: ModifierSet)
        /// 任意普通按键或鼠标按下
        case otherInput
    }

    public var interval: TimeInterval
    public static let maxHold: TimeInterval = 0.35

    private var downKey: ModifierKey?
    private var downTime: TimeInterval = 0
    private var clean = false
    private var lastTapKey: ModifierKey?
    private var lastUpTime: TimeInterval = 0

    public init(interval: TimeInterval = 0.3) {
        self.interval = interval
    }

    public static func key(forKeyCode code: UInt16) -> ModifierKey? {
        switch code {
        case 59, 62: .control
        case 58, 61: .option
        case 55, 54: .command
        case 56, 60: .shift
        default: nil
        }
    }

    static func flag(_ key: ModifierKey) -> ModifierSet {
        switch key {
        case .control: .control
        case .option: .option
        case .command: .command
        case .shift: .shift
        }
    }

    public mutating func reset() {
        downKey = nil
        clean = false
        lastTapKey = nil
    }

    /// 触发双击时返回对应的修饰键。
    public mutating func process(_ event: Event, at time: TimeInterval) -> ModifierKey? {
        switch event {
        case .otherInput:
            reset()
            return nil
        case .flagsChanged(let code, let flags):
            guard let key = Self.key(forKeyCode: code) else { return nil }
            let isDown = flags.contains(Self.flag(key))
            if isDown {
                if flags != Self.flag(key) {
                    reset()
                    return nil
                }
                if lastTapKey != key { lastTapKey = nil }
                downKey = key
                downTime = time
                clean = true
                return nil
            } else {
                defer { downKey = nil }
                guard downKey == key, clean, time - downTime <= Self.maxHold else {
                    reset()
                    return nil
                }
                if lastTapKey == key, downTime - lastUpTime <= interval {
                    reset()
                    return key
                }
                lastTapKey = key
                lastUpTime = time
                return nil
            }
        }
    }
}
