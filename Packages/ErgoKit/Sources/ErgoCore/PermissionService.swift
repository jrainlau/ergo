import AppKit
import ApplicationServices
import CoreGraphics
import ErgoPluginKit

public final class PermissionService: PermissionServicing {
    public init() {}

    public func status(_ permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .inputMonitoring:
            return CGPreflightListenEventAccess() ? .granted : .denied
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .pasteboard:
            switch NSPasteboard.general.accessBehavior {
            case .alwaysAllow: return .granted
            case .alwaysDeny: return .denied
            case .ask: return .notDetermined
            default: return .unknown
            }
        case .fullDiskAccess:
            let path = NSHomeDirectory() + "/Library/Safari/Bookmarks.plist"
            guard FileManager.default.fileExists(atPath: path) else { return .unknown }
            if let h = FileHandle(forReadingAtPath: path) {
                try? h.close()
                return .granted
            }
            return .denied
        }
    }

    public func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .pasteboard, .fullDiskAccess:
            openSystemSettings(for: permission)
        }
    }

    public func openSystemSettings(for permission: Permission) {
        let anchor: String
        switch permission {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .fullDiskAccess: anchor = "Privacy_AllFiles"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .pasteboard: anchor = ""
        }
        let s = anchor.isEmpty
            ? "x-apple.systempreferences:com.apple.preference.security"
            : "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    /// 重启 App（输入监控授权后通常需要）。
    public static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
