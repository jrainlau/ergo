import AppKit
import CoreGraphics
import ErgoCore

/// 位置计算（纯逻辑，便于测试）。
public enum LauncherGeometry {
    public static let defaultTopRatio: CGFloat = 0.22

    public static func origin(placement: LauncherPlacement?, size: NSSize, visibleFrame vf: NSRect) -> NSPoint {
        let cx = placement.map { vf.minX + CGFloat($0.centerXRatio) * vf.width } ?? vf.midX
        let top = placement.map { vf.maxY - CGFloat($0.topOffset) } ?? (vf.maxY - vf.height * defaultTopRatio)
        return clamp(origin: NSPoint(x: cx - size.width / 2, y: top - size.height), size: size, visibleFrame: vf)
    }

    public static func placement(for frame: NSRect, screenUUID: String, visibleFrame vf: NSRect) -> LauncherPlacement {
        LauncherPlacement(
            screenUUID: screenUUID,
            centerXRatio: Double((frame.midX - vf.minX) / max(vf.width, 1)),
            topOffset: Double(vf.maxY - frame.maxY)
        )
    }

    public static func clamp(origin: NSPoint, size: NSSize, visibleFrame vf: NSRect) -> NSPoint {
        var o = origin
        o.x = min(max(o.x, vf.minX), max(vf.minX, vf.maxX - size.width))
        o.y = max(o.y, vf.minY)
        if o.y + size.height > vf.maxY { o.y = vf.maxY - size.height }
        return o
    }

    /// 改变尺寸时保持顶边与水平中心不变。
    public static func resized(old: NSRect, newSize: NSSize, visibleFrame vf: NSRect) -> NSRect {
        let o = NSPoint(x: old.midX - newSize.width / 2, y: old.maxY - newSize.height)
        var origin = o
        origin.x = min(max(origin.x, vf.minX), max(vf.minX, vf.maxX - newSize.width))
        origin.y = max(origin.y, vf.minY)
        return NSRect(origin: origin, size: newSize)
    }

    public static func screenUUID(_ screen: NSScreen) -> String {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return "unknown" }
        let id = CGDirectDisplayID(num.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "display-\(id)" }
        return (CFUUIDCreateString(nil, uuid) as String?) ?? "display-\(id)"
    }

    public static func screen(withUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { screenUUID($0) == uuid }
    }
}

public enum LauncherMetrics {
    public static let customWidth: CGFloat = 760
    public static let previewMinWidth: CGFloat = 860
    public static let previewRows = 9
}
