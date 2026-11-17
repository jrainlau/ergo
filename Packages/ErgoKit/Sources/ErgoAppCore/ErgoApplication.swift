import AppKit

public enum ErgoApplication {
    static var delegate: NSObject?
    public static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
