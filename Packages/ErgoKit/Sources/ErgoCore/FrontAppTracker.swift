import AppKit
import ErgoPluginKit

public final class FrontAppTracker: FrontAppProviding {
    public private(set) var previousApplication: NSRunningApplication?
    public init() {}

    /// 在显示启动器之前调用。
    public func captureNow() {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = app
        }
    }
}
