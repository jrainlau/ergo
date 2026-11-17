import CoreGraphics
import Foundation
import ErgoPluginKit

/// 通过 CGEventTap（listenOnly）监听“双击修饰键”。需要输入监控权限。
public final class ModifierTapMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = DoubleTapDetector()
    private var bindings: [ModifierKey: [() -> Void]] = [:]
    private var healthTimer: Timer?

    public init() {}

    public var isRunning: Bool { tap != nil }

    public func setBindings(_ b: [ModifierKey: [() -> Void]], interval: TimeInterval) {
        bindings = b
        detector.interval = interval
        if b.isEmpty { stop() } else if tap == nil { _ = start() }
    }

    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        guard CGPreflightListenEventAccess() else { return false }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: modifierTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        healthTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let t = self.tap, !CGEvent.tapIsEnabled(tap: t) else { return }
                CGEvent.tapEnable(tap: t, enable: true)
            }
        }
        return true
    }

    public func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
        detector.reset()
    }

    fileprivate func handle(type: CGEventType, keyCode: UInt16, flags: ModifierSet, time: TimeInterval) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        case .flagsChanged:
            if let key = detector.process(.flagsChanged(keyCode: keyCode, flags: flags), at: time) {
                bindings[key]?.forEach { $0() }
            }
        default:
            _ = detector.process(.otherInput, at: time)
        }
    }
}

private nonisolated func modifierTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let f = event.flags
    var flags: ModifierSet = []
    if f.contains(.maskCommand) { flags.insert(.command) }
    if f.contains(.maskAlternate) { flags.insert(.option) }
    if f.contains(.maskControl) { flags.insert(.control) }
    if f.contains(.maskShift) { flags.insert(.shift) }
    let time = TimeInterval(event.timestamp) / 1_000_000_000
    let ptr = UInt(bitPattern: refcon)
    MainActor.assumeIsolated {
        let monitor = Unmanaged<ModifierTapMonitor>.fromOpaque(UnsafeRawPointer(bitPattern: ptr)!).takeUnretainedValue()
        monitor.handle(type: type, keyCode: keyCode, flags: flags, time: time)
    }
    return Unmanaged.passUnretained(event)
}
