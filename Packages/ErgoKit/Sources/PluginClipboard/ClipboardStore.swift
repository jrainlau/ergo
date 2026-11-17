import Foundation
import GRDB

public nonisolated final class ClipboardStore: Sendable {
    let queue: DatabaseQueue
    public let blobsDir: URL
    public let thumbsDir: URL

    public init(directory: URL, inMemory: Bool = false) throws {
        blobsDir = directory.appendingPathComponent("blobs", isDirectory: true)
        thumbsDir = directory.appendingPathComponent("thumbs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        queue = inMemory ? try DatabaseQueue() : try DatabaseQueue(path: directory.appendingPathComponent("clipboard.sqlite").path)
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "clip_item") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("textContent", .text)
                t.column("blobPath", .text)
                t.column("thumbPath", .text)
                t.column("metaJSON", .text)
                t.column("contentHash", .text).notNull().unique()
                t.column("sourceBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("createdAt", .double).notNull()
                t.column("lastCopiedAt", .double).notNull()
                t.column("copyCount", .integer).notNull().defaults(to: 1)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "clip_item_order", on: "clip_item", columns: ["isPinned", "lastCopiedAt"])
        }
        try m.migrate(queue)
    }

    public func blobURL(_ item: ClipItem) -> URL? { item.blobPath.map { blobsDir.appendingPathComponent($0) } }
    public func thumbURL(_ item: ClipItem) -> URL? { item.thumbPath.map { thumbsDir.appendingPathComponent($0) } }

    /// 内容哈希已存在时：更新时间与次数并返回 true。
    public func touch(hash: String, at time: Double = Date().timeIntervalSince1970) throws -> Bool {
        try queue.write { db in
            try db.execute(sql: "UPDATE clip_item SET lastCopiedAt = ?, copyCount = copyCount + 1 WHERE contentHash = ?", arguments: [time, hash])
            return db.changesCount > 0
        }
    }

    public func touch(id: String, at time: Double = Date().timeIntervalSince1970) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE clip_item SET lastCopiedAt = ?, copyCount = copyCount + 1 WHERE id = ?", arguments: [time, id])
        }
    }

    public func insert(_ item: ClipItem) throws {
        try queue.write { db in try item.insert(db) }
    }

    public func item(id: String) throws -> ClipItem? {
        try queue.read { db in try ClipItem.fetchOne(db, key: id) }
    }

    public func count() throws -> Int {
        try queue.read { db in try ClipItem.fetchCount(db) }
    }

    public func search(_ text: String, limit: Int = 200) throws -> [ClipItem] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return try queue.read { db in
            var sql = "SELECT * FROM clip_item"
            var args: [DatabaseValueConvertible] = []
            if !words.isEmpty {
                let clauses = words.map { _ in "(title LIKE ? ESCAPE '\\' OR textContent LIKE ? ESCAPE '\\')" }
                sql += " WHERE " + clauses.joined(separator: " AND ")
                for w in words {
                    let escaped = w.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "%", with: "\\%")
                        .replacingOccurrences(of: "_", with: "\\_")
                    args.append("%\(escaped)%")
                    args.append("%\(escaped)%")
                }
            }
            sql += " ORDER BY isPinned DESC, lastCopiedAt DESC LIMIT ?"
            args.append(limit)
            return try ClipItem.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    public func setPinned(_ id: String, _ pinned: Bool) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE clip_item SET isPinned = ? WHERE id = ?", arguments: [pinned, id])
        }
    }

    public func delete(id: String) throws {
        let item = try item(id: id)
        _ = try queue.write { db in try ClipItem.deleteOne(db, key: id) }
        removeFiles(for: [item].compactMap { $0 })
    }

    public func deleteAll() throws {
        let all = try queue.read { db in try ClipItem.fetchAll(db) }
        _ = try queue.write { db in try ClipItem.deleteAll(db) }
        removeFiles(for: all)
    }

    /// 按保留时长与数量上限清理；retention 为 nil 表示永久保留。返回删除条数。
    @discardableResult
    public func cleanup(retention: TimeInterval?, maxItems: Int, now: Date = Date()) throws -> Int {
        var doomed: [ClipItem] = []
        try queue.write { db in
            if let retention {
                let cutoff = now.timeIntervalSince1970 - retention
                doomed += try ClipItem.fetchAll(db, sql: "SELECT * FROM clip_item WHERE isPinned = 0 AND lastCopiedAt < ?", arguments: [cutoff])
            }
            let total = try ClipItem.fetchCount(db)
            let alreadyDoomed = Set(doomed.map(\.id))
            let remaining = total - doomed.count
            if remaining > maxItems {
                let extra = try ClipItem.fetchAll(db, sql: "SELECT * FROM clip_item WHERE isPinned = 0 ORDER BY lastCopiedAt ASC")
                    .filter { !alreadyDoomed.contains($0.id) }
                    .prefix(remaining - maxItems)
                doomed += extra
            }
            for item in doomed { _ = try ClipItem.deleteOne(db, key: item.id) }
        }
        removeFiles(for: doomed)
        removeOrphans()
        return doomed.count
    }

    private func removeFiles(for items: [ClipItem]) {
        let fm = FileManager.default
        for i in items {
            if let u = blobURL(i) { try? fm.removeItem(at: u) }
            if let u = thumbURL(i) { try? fm.removeItem(at: u) }
        }
    }

    private func removeOrphans() {
        let fm = FileManager.default
        let rows = (try? queue.read { db in try ClipItem.fetchAll(db) }) ?? []
        let blobs = Set(rows.compactMap(\.blobPath))
        let thumbs = Set(rows.compactMap(\.thumbPath))
        for (dir, keep) in [(blobsDir, blobs), (thumbsDir, thumbs)] {
            for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(f) {
                try? fm.removeItem(at: dir.appendingPathComponent(f))
            }
        }
    }
}
