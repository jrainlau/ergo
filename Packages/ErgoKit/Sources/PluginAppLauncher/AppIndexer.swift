import Foundation
import ErgoPluginSupport

public nonisolated struct AppEntry: Codable, Equatable, Sendable {
    public var path: String
    public var bundleID: String?
    public var name: String
    public var aliases: [String]
    public var pinyinFull: String
    public var pinyinInitials: String

    public var url: URL { URL(fileURLWithPath: path) }
}

public nonisolated enum AppIndexer {
    public static let defaultDirectories = [
        "/Applications", "/Applications/Utilities",
        "/System/Applications", "/System/Applications/Utilities",
        "~/Applications",
    ]

    public static func expand(_ p: String) -> String { (p as NSString).expandingTildeInPath }

    public static func scan(directories: [String], depth: Int, excludedIDs: Set<String>) -> [AppEntry] {
        var result: [AppEntry] = []
        var seenIDs = Set<String>()
        var seenPaths = Set<String>()
        let fm = FileManager.default

        func add(_ url: URL) {
            let path = url.resolvingSymlinksInPath().path
            guard seenPaths.insert(path).inserted, let entry = makeEntry(url: url) else { return }
            if let id = entry.bundleID {
                if excludedIDs.contains(id) { return }
                guard seenIDs.insert(id).inserted else { return }
            }
            if excludedIDs.contains(entry.path) { return }
            result.append(entry)
        }

        for dir in directories {
            let root = URL(fileURLWithPath: expand(dir), isDirectory: true)
            guard let e = fm.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in e {
                if e.level > depth + 1 { e.skipDescendants(); continue }
                if url.pathExtension == "app" { add(url) }
            }
        }
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        if fm.fileExists(atPath: finder.path) { add(finder) }
        return result
    }

    static func makeEntry(url: URL) -> AppEntry? {
        let stem = url.deletingPathExtension().lastPathComponent
        var display = FileManager.default.displayName(atPath: url.path)
        if display.hasSuffix(".app") { display.removeLast(4) }
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary
        let localized = bundle?.localizedInfoDictionary
        var names: [String] = [display, stem]
        for k in ["CFBundleDisplayName", "CFBundleName"] {
            if let v = localized?[k] as? String { names.append(v) }
            if let v = info?[k] as? String { names.append(v) }
        }
        var seen = Set<String>()
        let unique = names.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard let primary = unique.first else { return nil }
        let py = Pinyin.convert(primary)
        return AppEntry(
            path: url.path,
            bundleID: info?["CFBundleIdentifier"] as? String,
            name: primary,
            aliases: Array(unique.dropFirst()),
            pinyinFull: py.hasCJK ? py.full : "",
            pinyinInitials: py.hasCJK ? py.initials : ""
        )
    }

    public static func score(query: String, entry: AppEntry) -> Double? {
        var best = FuzzyMatcher.score(query: query, candidate: entry.name, pinyinFull: entry.pinyinFull, pinyinInitials: entry.pinyinInitials)
        for a in entry.aliases {
            let py = Pinyin.convert(a)
            if let s = FuzzyMatcher.score(query: query, candidate: a, pinyinFull: py.hasCJK ? py.full : nil, pinyinInitials: py.hasCJK ? py.initials : nil) {
                best = max(best ?? 0, s * 0.95)
            }
        }
        return best
    }
}
