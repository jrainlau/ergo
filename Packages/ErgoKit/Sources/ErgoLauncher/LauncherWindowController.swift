import AppKit
import OSLog
import SwiftUI
import ErgoCore
import ErgoPluginKit
import ErgoUI

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class LauncherWindowController: NSObject {
    public let model: LauncherModel
    private let services: CoreServices
    private let panel: LauncherPanel
    private let hosting: NSHostingView<LauncherRootView>
    private var keyMonitor: Any?
    private var isProgrammaticMove = false
    private var saveTask: Task<Void, Never>?
    private var appliedMaterial: PanelMaterial?

    public var isVisible: Bool { panel.isVisible }
    public var onOpenSettings: () -> Void = {} {
        didSet { model.requestOpenSettings = onOpenSettings }
    }

    public init(host: PluginHost, services: CoreServices) {
        self.services = services
        self.model = LauncherModel(host: host, services: services)
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: Theme.inputHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        hosting = NSHostingView(rootView: LauncherRootView(model: model))
        super.init()

        hosting.sizingOptions = []
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.title = "Ergo"

        model.requestHide = { [weak self] in self?.hide() }
        model.onLayoutChange = { [weak self] in self?.updateFrame() }

        let bridge = services.launcher
        bridge.visibleProvider = { [weak self] in self?.isVisible ?? false }
        bridge.onShow = { [weak self] scope, q in self?.show(scope: scope, query: q) }
        bridge.onHide = { [weak self] in self?.hide() }
        bridge.onSetQuery = { [weak self] q in self?.model.query = q }
        bridge.onRefresh = { [weak self] in self?.model.refresh() }
        services.paste.hideLauncher = { [weak self] in self?.hide() }

        NotificationCenter.default.addObserver(self, selector: #selector(didResignKey), name: NSWindow.didResignKeyNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(didMove), name: NSWindow.didMoveNotification, object: panel)

        // 预热：App 启动时即完成布局，唤起时无需创建
        applyMaterial()
        panel.setContentSize(NSSize(width: model.panelWidth, height: model.panelHeight))
    }

    // MARK: 显示 / 隐藏

    public func toggle() {
        if panel.isVisible { hide() } else { show(scope: nil, query: nil) }
    }

    private static let signposter = OSSignposter(subsystem: "com.jrainlau.ergo", category: "launcher")
    private static let log = Logger(subsystem: "com.jrainlau.ergo", category: "launcher")

    public func show(scope: PluginID?, query: String?) {
        let wasVisible = panel.isVisible
        let signpostID = Self.signposter.makeSignpostID()
        let state = Self.signposter.beginInterval("show", id: signpostID)
        let started = ContinuousClock.now
        defer {
            Self.signposter.endInterval("show", state)
            let ms = Double((ContinuousClock.now - started).components.attoseconds) / 1e15
            Self.log.debug("show took \(ms, format: .fixed(precision: 1)) ms")
        }
        if !wasVisible {
            services.frontApp.captureNow()
            model.resetForShow(keepQuery: services.appSettings.value.keepLastQuery)
        }
        if let scope {
            model.enterScope(scope, query: query ?? "")
        } else if let query {
            model.query = query
        }
        applyMaterial()
        if !wasVisible {
            let size = NSSize(width: model.panelWidth, height: model.panelHeight)
            let screen = targetScreen()
            let vf = screen.visibleFrame
            let origin = LauncherGeometry.origin(placement: services.appSettings.value.placement, size: size, visibleFrame: vf)
            setFrameProgrammatically(NSRect(origin: origin, size: size))
            panel.alphaValue = 0
        }
        panel.makeKeyAndOrderFront(nil)
        focusInput()
        installKeyMonitor()
        if !wasVisible {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.alphaValue = 1
            } else {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    panel.animator().alphaValue = 1
                }
            }
        }
    }

    public func hide() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
        model.didHide()
    }

    public func resetPlacement() {
        services.appSettings.value.placement = nil
    }

    private func focusInput() {
        if let f = model.textField, f.window === panel {
            panel.makeFirstResponder(f)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, let f = self.model.textField, f.window === self.panel else { return }
            if !(self.panel.firstResponder is NSTextView) { self.panel.makeFirstResponder(f) }
        }
    }

    // MARK: 位置与尺寸

    private func targetScreen() -> NSScreen {
        let s = services.appSettings.value
        switch s.showOnScreen {
        case .main:
            return NSScreen.screens.first ?? NSScreen.main!
        case .last:
            if let p = s.placement, let sc = LauncherGeometry.screen(withUUID: p.screenUUID) { return sc }
            fallthrough
        case .mouse:
            let loc = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        }
    }

    private func setFrameProgrammatically(_ rect: NSRect) {
        isProgrammaticMove = true
        panel.setFrame(rect, display: true, animate: false)
        isProgrammaticMove = false
    }

    private func updateFrame() {
        let size = NSSize(width: model.panelWidth, height: model.panelHeight)
        guard panel.isVisible else {
            panel.setContentSize(size)
            return
        }
        guard panel.frame.size != size else { return }
        let vf = (panel.screen ?? targetScreen()).visibleFrame
        setFrameProgrammatically(LauncherGeometry.resized(old: panel.frame, newSize: size, visibleFrame: vf))
    }

    @objc private func didMove() {
        guard !isProgrammaticMove, panel.isVisible else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, let screen = self.panel.screen else { return }
            let p = LauncherGeometry.placement(for: self.panel.frame, screenUUID: LauncherGeometry.screenUUID(screen), visibleFrame: screen.visibleFrame)
            self.services.appSettings.value.placement = p
        }
    }

    @objc private func didResignKey() {
        guard panel.isVisible, services.appSettings.value.hideOnResignKey else { return }
        // 延迟一拍：避免窗口内部焦点切换（如弹出菜单）误触发
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.hide()
        }
    }

    // MARK: 材质

    private func applyMaterial() {
        let m = services.appSettings.value.material
        guard appliedMaterial != m else { return }
        appliedMaterial = m
        hosting.removeFromSuperview()
        switch m {
        case .regular, .clear:
            let glass = NSGlassEffectView()
            glass.cornerRadius = Theme.panelCornerRadius
            glass.style = m == .clear ? .clear : .regular
            glass.contentView = hosting
            panel.contentView = glass
        case .opaque:
            let v = NSVisualEffectView()
            v.material = .hudWindow
            v.blendingMode = .behindWindow
            v.state = .active
            v.wantsLayer = true
            v.layer?.cornerRadius = Theme.panelCornerRadius
            v.layer?.cornerCurve = .continuous
            v.layer?.masksToBounds = true
            hosting.frame = v.bounds
            hosting.autoresizingMask = [.width, .height]
            v.addSubview(hosting)
            panel.contentView = v
        }
    }

    // MARK: 键盘

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel else { return event }
        // 输入法正在组字：全部放行
        if let tv = panel.firstResponder as? NSTextView, tv.hasMarkedText() { return event }
        guard let press = KeyTranslator.press(from: event) else { return event }
        return model.handle(press) ? nil : event
    }
}
