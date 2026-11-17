import Quartz
import SwiftUI

public struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    public init(url: URL) { self.url = url }

    public func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .compact)!
        v.autostarts = true
        v.previewItem = url as NSURL
        return v
    }

    public func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? NSURL) as URL? != url { v.previewItem = url as NSURL }
    }

    public static func dismantleNSView(_ v: QLPreviewView, coordinator: ()) {
        v.close()
    }
}
