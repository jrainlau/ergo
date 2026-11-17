import AppKit
import ErgoPluginKit
import ErgoUI

public final class IconProvider: IconProviding {
    public init() {}
    public func icon(for url: URL, size: CGFloat) -> NSImage {
        IconCache.shared.icon(for: url, size: size)
    }
}
