import Foundation
import ErgoPluginSupport

public nonisolated struct FileHit: Sendable, Equatable {
    public var path: String
    public var displayName: String
    public var isDirectory: Bool
    public var lastUsed: Date?
    public var modified: Date?
    public var url: URL { URL(fileURLWithPath: path) }
}

public nonisolated struct FileSearchSettings: Codable, Equatable, Sendable {
    public var searchContent = false
    public var homeOnly = false
    public var excludedPatterns: [String] = FileQuery.defaultExclusions
    public init() {}
}

public nonisolated enum FileQuery {
    public static let defaultExclusions = ["~/Library", "/System", "/Library", "/private", "*/node_modules/*", "*/.git/*"]

    public static func terms(from text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// 转义 Spotlight 查询字符串中的特殊字符。
    public static func escape(_ term: String) -> String {
        var out = ""
        for ch in term {
            if ch == "\\" || ch == "\"" || ch == "*" { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    public static func predicateString(terms: [String], searchContent: Bool) -> String? {
        guard !terms.isEmpty else { return nil }
        let parts = terms.map { t -> String in
            let e = escape(t)
            var s = "(kMDItemFSName == \"*\(e)*\"cd || kMDItemDisplayName == \"*\(e)*\"cd"
            if searchContent { s += " || kMDItemTextContent == \"\(e)*\"cd" }
            return s + ")"
        }
        return parts.joined(separator: " && ") + " && kMDItemContentType != \"com.apple.application-bundle\""
    }

    public static func isExcluded(_ path: String, patterns: [String], home: String = NSHomeDirectory()) -> Bool {
        for raw in patterns {
            let p = raw.hasPrefix("~") ? home + raw.dropFirst() : raw
            if p.hasPrefix("*") && p.hasSuffix("*") && p.count > 2 {
                let mid = String(p.dropFirst().dropLast())
                if path.contains(mid) { return true }
            } else if path == p || path.hasPrefix(p + "/") {
                return true
            }
        }
        return false
    }

    public static func score(_ hit: FileHit, query: String, now: Date = Date(), home: String = NSHomeDirectory()) -> Double {
        let base = (hit.displayName as NSString).deletingPathExtension
        let fuzzy = FuzzyMatcher.score(query: query, candidate: base) ?? FuzzyMatcher.score(query: query, candidate: hit.displayName) ?? 0.1
        var s = fuzzy * 0.6
        if let d = hit.lastUsed ?? hit.modified {
            let age = now.timeIntervalSince(d)
            if age < 86_400 { s += 0.25 } else if age < 7 * 86_400 { s += 0.18 } else if age < 30 * 86_400 { s += 0.10 } else { s += 0.03 }
        }
        if hit.isDirectory { s += 0.03 }
        if hit.path.hasPrefix(home + "/") {
            let depth = hit.path.dropFirst(home.count + 1).split(separator: "/").count - 1
            if depth > 3 { s -= 0.02 * Double(depth - 3) }
        }
        return max(0, s)
    }
}
