import AppKit
import SwiftUI
import ErgoPluginKit

public final class HUDService: HUDPresenting {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    public init() {}

    public func show(_ text: String, symbol: String?) {
        hideTask?.cancel()
        let host = NSHostingView(rootView: HUDView(text: text, symbol: symbol))
        let size = host.fittingSize

        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.isReleasedWhenClosed = false
            self.panel = p
            return p
        }()

        let glass = NSGlassEffectView()
        glass.cornerRadius = size.height / 2
        glass.contentView = host
        panel.contentView = glass

        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.minY + vf.height / 5)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, let self, let panel = self.panel else { return }
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            }
            if !Task.isCancelled { panel.orderOut(nil) }
        }
    }
}

private struct HUDView: View {
    let text: String
    let symbol: String?

    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
