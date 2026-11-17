import AppKit

@MainActor
public final class IconCache {
    public static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    private var bundleURLCache: [String: URL?] = [:]

    public func icon(forPath path: String, size: CGFloat) -> NSImage {
        let key = "\(path)#\(Int(size))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: size, height: size)
        cache.setObject(img, forKey: key)
        return img
    }

    public func icon(for url: URL, size: CGFloat) -> NSImage {
        icon(forPath: url.path, size: size)
    }

    public func icon(bundleID: String, size: CGFloat) -> NSImage? {
        let url: URL?
        if let cached = bundleURLCache[bundleID] {
            url = cached
        } else {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            bundleURLCache[bundleID] = url
        }
        guard let url else { return nil }
        return icon(for: url, size: size)
    }
}
