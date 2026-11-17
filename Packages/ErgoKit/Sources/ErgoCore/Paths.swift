import Foundation
import ErgoPluginKit

public enum ErgoPaths {
    public static let bundleID = "com.jrainlau.ergo"

    public static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ensure(base.appendingPathComponent("Ergo", isDirectory: true))
    }

    public static var caches: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ensure(base.appendingPathComponent(bundleID, isDirectory: true))
    }

    public static func pluginData(_ id: PluginID) -> URL {
        ensure(appSupport.appendingPathComponent("Plugins", isDirectory: true).appendingPathComponent(id.rawValue, isDirectory: true))
    }

    public static func pluginCache(_ id: PluginID) -> URL {
        ensure(caches.appendingPathComponent(id.rawValue, isDirectory: true))
    }

    public static var databaseURL: URL { appSupport.appendingPathComponent("ergo.sqlite") }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
