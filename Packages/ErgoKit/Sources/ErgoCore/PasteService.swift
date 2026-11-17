import AppKit
import ApplicationServices
import ErgoPluginKit

public final class PasteService: PasteServicing {
    public static let markerType = NSPasteboard.PasteboardType("com.jrainlau.ergo.marker")

    private let frontApp: FrontAppTracker
    private let hud: any HUDPresenting
    public var hideLauncher: () -> Void = {}

    public init(frontApp: FrontAppTracker, hud: any HUDPresenting) {
        self.frontApp = frontApp
        self.hud = hud
    }

    public func copy(_ content: PasteContent, marker: String?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch content {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .richText(let rtf, let plain):
            pb.setData(rtf, forType: .rtf)
            pb.setString(plain, forType: .string)
        case .image(let png):
            pb.setData(png, forType: .png)
            if let img = NSImage(data: png), let tiff = img.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        case .fileURLs(let urls):
            pb.writeObjects(urls as [NSURL])
        case .url(let url):
            pb.writeObjects([url as NSURL])
            pb.setString(url.absoluteString, forType: .string)
        case .color(let c):
            pb.writeObjects([c])
        }
        if let marker { pb.setString(marker, forType: Self.markerType) }
    }

    public func paste(_ content: PasteContent, marker: String?, restoreClipboard: Bool) async -> PasteResult {
        let snapshot = restoreClipboard ? Self.snapshot() : nil
        copy(content, marker: marker)
        hideLauncher()

        guard AXIsProcessTrusted() else {
            hud.show("已复制，按 ⌘V 粘贴", symbol: "doc.on.clipboard")
            return .copiedOnly(reason: "未授予辅助功能权限")
        }

        if let target = frontApp.previousApplication, NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            target.activate()
            try? await Task.sleep(for: .milliseconds(100))
        } else {
            try? await Task.sleep(for: .milliseconds(50))
        }
        Self.postKey(0x09, flags: .maskCommand)

        if let snapshot {
            try? await Task.sleep(for: .milliseconds(400))
            Self.restore(snapshot)
        }
        return .pasted
    }

    public func postKeystrokes(leftArrowCount: Int) async {
        guard leftArrowCount > 0, AXIsProcessTrusted() else { return }
        try? await Task.sleep(for: .milliseconds(60))
        for _ in 0..<leftArrowCount {
            Self.postKey(0x7B, flags: [])
        }
    }

    private static func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cgSessionEventTap)
        }
    }

    private struct Snapshot { var items: [[(NSPasteboard.PasteboardType, Data)]] }

    private static func snapshot() -> Snapshot {
        let items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        return Snapshot(items: items)
    }

    private static func restore(_ s: Snapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let objs: [NSPasteboardItem] = s.items.map { entries in
            let item = NSPasteboardItem()
            for (t, d) in entries { item.setData(d, forType: t) }
            return item
        }
        objs.first?.setString("restore", forType: markerType)
        if !objs.isEmpty { pb.writeObjects(objs) }
    }
}
