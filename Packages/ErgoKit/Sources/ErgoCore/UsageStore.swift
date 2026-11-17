import Foundation
import GRDB
import ErgoPluginKit

/// 使用频率记录：内存缓存 + SQLite 异步落盘。
public final class UsageStore: UsageRecording {
    private let queue: DatabaseQueue?
    private var perQuery: [String: [String: Int]] = [:]   // itemID -> query -> count
    private var totals: [String: Int] = [:]

    /// url 为 nil 时只使用内存（测试用）。
    public init(url: URL?) {
        if let url, let q = try? DatabaseQueue(path: url.path) {
            queue = q
            try? Self.migrate(q)
            load()
        } else {
            queue = nil
        }
    }

    private static func migrate(_ q: DatabaseQueue) throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "usage") { t in
                t.column("itemID", .text).notNull()
                t.column("query", .text).notNull()
                t.column("count", .integer).notNull().defaults(to: 0)
                t.column("lastUsedAt", .double).notNull()
                t.primaryKey(["itemID", "query"])
            }
        }
        try m.migrate(q)
    }

    private func load() {
        guard let queue else { return }
        let rows: [(String, String, Int)] = (try? queue.read { db in
            try Row.fetchAll(db, sql: "SELECT itemID, query, count FROM usage").map { ($0["itemID"], $0["query"], $0["count"]) }
        }) ?? []
        for (id, q, c) in rows {
            perQuery[id, default: [:]][q] = c
            totals[id, default: 0] += c
        }
    }

    static func norm(_ q: String) -> String {
        q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public func record(itemID: String, query: String) {
        let q = Self.norm(query)
        perQuery[itemID, default: [:]][q, default: 0] += 1
        totals[itemID, default: 0] += 1
        guard let queue else { return }
        let now = Date().timeIntervalSince1970
        Task {
            try? await queue.write { db in
                try db.execute(sql: """
                    INSERT INTO usage (itemID, query, count, lastUsedAt) VALUES (?, ?, 1, ?)
                    ON CONFLICT(itemID, query) DO UPDATE SET count = count + 1, lastUsedAt = excluded.lastUsedAt
                    """, arguments: [itemID, q, now])
            }
        }
    }

    public func boost(itemID: String, query: String) -> Double {
        guard let queries = perQuery[itemID] else { return 0 }
        let q = Self.norm(query)
        func part(_ c: Int) -> Double { min(0.15, 0.05 * log2(1 + Double(c))) }
        var score = 0.0
        if !q.isEmpty {
            score += part(queries[q] ?? 0)
            var related = 0
            for (k, c) in queries where k != q && !k.isEmpty && (k.hasPrefix(q) || q.hasPrefix(k)) {
                related = max(related, c)
            }
            score = max(score, 0.5 * part(related))
        }
        score += min(0.05, 0.01 * log2(1 + Double(totals[itemID] ?? 0)))
        return min(0.2, score)
    }
}
