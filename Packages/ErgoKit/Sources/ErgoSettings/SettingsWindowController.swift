import AppKit
import SwiftUI
import ErgoCore
import ErgoPluginKit

public enum SettingsPage: Hashable {
    case general, appearance, permissions
    case plugin(PluginID)
    case about
}

@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let host: PluginHost
    private let services: CoreServices
    private var window: NSWindow?
    private let navigation = SettingsNavigation()
    public var onResetPlacement: () -> Void = {}

    public init(host: PluginHost, services: CoreServices) {
        self.host = host
        self.services = services
    }

    public func show(page: SettingsPage? = nil, openManagement: Bool = false) {
        if let page {
            navigation.page = page
            if openManagement, case .plugin(let id) = page { navigation.pendingManagement = id }
        }
        if window == nil {
            let root = SettingsRootView(host: host, services: services, nav: navigation, resetPlacement: { [weak self] in self?.onResetPlacement() })
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            w.title = "Ergo 设置"
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            let hc = NSHostingController(rootView: root)
            hc.sizingOptions = []
            w.contentViewController = hc
            w.setContentSize(NSSize(width: 860, height: 620))
            w.minSize = NSSize(width: 760, height: 520)
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    var page: SettingsPage = .general
    var pendingManagement: PluginID?
}
