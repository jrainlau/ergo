import Foundation
import GRDB
import ErgoPluginSupport

public nonisolated struct SnippetCollection: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable, Sendable {
    public static let databaseTableName = "snippet_collection"
    public var id: String
    public var name: String
    public var sortOrder: Int
}

public nonisolated struct Snippet: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable, Sendable {
    public static let databaseTableName = "snippet"
    public var id: String
    public var collectionID: String
    public var title: String
    public var keyword: String
    public var content: String
    public var useCount: Int
    public var lastUsedAt: Double?
    public var sortOrder: Int
    public var createdAt: Double
    public var updatedAt: Double
}

/// 导入导出格式。
public nonisolated struct SnippetLibraryFile: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var title: String
        public var keyword: String
        public var content: String
        public var useCount: Int
    }
    public struct Group: Codable, Equatable, Sendable {
        public var name: String
        public var snippets: [Entry]
    }
    public var version = 1
    public var collections: [Group]
}

public nonisolated final class SnippetStore: Sendable {
    let queue: DatabaseQueue

    public init(path: String? = nil) throws {
        queue = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "snippet_collection") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "snippet") { t in
                t.column("id", .text).primaryKey()
                t.column("collectionID", .text).notNull().indexed().references("snippet_collection", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("keyword", .text).notNull().defaults(to: "")
                t.column("content", .text).notNull().defaults(to: "")
                t.column("useCount", .integer).notNull().defaults(to: 0)
                t.column("lastUsedAt", .double)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
        }
        try m.migrate(queue)
        try seedIfEmpty()
    }

    private func seedIfEmpty() throws {
        let empty = try queue.read { try SnippetCollection.fetchCount($0) == 0 }
        guard empty else { return }
        let c = try addCollection(name: "默认")
        _ = try addSnippet(collectionID: c.id, title: "今天的日期", keyword: "rq", content: "{date}")
        _ = try addSnippet(collectionID: c.id, title: "邮件签名", keyword: "qm", content: "此致\n敬礼！\n\n{datetime}{cursor}")
    }

    // MARK: 读取
    public func collections() throws -> [SnippetCollection] {
        try queue.read { try SnippetCollection.order(Column("sortOrder"), Column("name")).fetchAll($0) }
    }

    public func snippets(in collectionID: String? = nil) throws -> [Snippet] {
        try queue.read { db in
            var req = Snippet.all()
            if let collectionID { req = req.filter(Column("collectionID") == collectionID) }
            return try req.order(Column("sortOrder"), Column("createdAt")).fetchAll(db)
        }
    }

    public func snippet(id: String) throws -> Snippet? { try queue.read { try Snippet.fetchOne($0, key: id) } }

    // MARK: 分组
    @discardableResult
    public func addCollection(name: String) throws -> SnippetCollection {
        try queue.write { db in
            let next = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM snippet_collection") ?? -1) + 1
            let c = SnippetCollection(id: UUID().uuidString, name: name, sortOrder: next)
            try c.insert(db)
            return c
        }
    }

    public func renameCollection(id: String, name: String) throws {
        try queue.write { try $0.execute(sql: "UPDATE snippet_collection SET name = ? WHERE id = ?", arguments: [name, id]) }
    }

    public func deleteCollection(id: String) throws {
        _ = try queue.write { try SnippetCollection.deleteOne($0, key: id) }
    }

    // MARK: 常用语
    @discardableResult
    public func addSnippet(collectionID: String, title: String, keyword: String = "", content: String = "", useCount: Int = 0, now: Date = Date()) throws -> Snippet {
        try queue.write { db in
            let next = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM snippet WHERE collectionID = ?", arguments: [collectionID]) ?? -1) + 1
            let t = now.timeIntervalSince1970
            let s = Snippet(id: UUID().uuidString, collectionID: collectionID, title: title, keyword: keyword, content: content,
                            useCount: useCount, lastUsedAt: nil, sortOrder: next, createdAt: t, updatedAt: t)
            try s.insert(db)
            return s
        }
    }

    public func update(_ s: Snippet) throws {
        var s = s
        s.updatedAt = Date().timeIntervalSince1970
        try queue.write { try s.update($0) }
    }

    public func deleteSnippet(id: String) throws {
        _ = try queue.write { try Snippet.deleteOne($0, key: id) }
    }

    public func recordUse(id: String, at date: Date = Date()) throws {
        try queue.write {
            try $0.execute(sql: "UPDATE snippet SET useCount = useCount + 1, lastUsedAt = ? WHERE id = ?", arguments: [date.timeIntervalSince1970, id])
        }
    }

    /// 按给定顺序重写 sortOrder。
    public func reorder(ids: [String]) throws {
        try queue.write { db in
            for (i, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE snippet SET sortOrder = ? WHERE id = ?", arguments: [i, id])
            }
        }
    }

    public func move(snippetID: String, to collectionID: String) throws {
        try queue.write { try $0.execute(sql: "UPDATE snippet SET collectionID = ? WHERE id = ?", arguments: [collectionID, snippetID]) }
    }

    // MARK: 导入导出
    public func exportLibrary() throws -> Data {
        let cols = try collections()
        let all = try snippets()
        let file = SnippetLibraryFile(collections: cols.map { c in
            .init(name: c.name, snippets: all.filter { $0.collectionID == c.id }.map {
                .init(title: $0.title, keyword: $0.keyword, content: $0.content, useCount: $0.useCount)
            })
        })
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(file)
    }

    /// 合并导入：同名分组合并；标题与内容都相同的跳过。返回新增条数。
    @discardableResult
    public func importLibrary(_ data: Data) throws -> Int {
        let file = try JSONDecoder().decode(SnippetLibraryFile.self, from: data)
        var added = 0
        for g in file.collections {
            let existing = try collections().first { $0.name == g.name }
            let col = try existing ?? addCollection(name: g.name)
            let current = try snippets(in: col.id)
            for e in g.snippets where !current.contains(where: { $0.title == e.title && $0.content == e.content }) {
                try addSnippet(collectionID: col.id, title: e.title, keyword: e.keyword, content: e.content, useCount: e.useCount)
                added += 1
            }
        }
        return added
    }
}

public nonisolated enum SnippetMatcher {
    /// 返回 0...1.1 的分数，nil 为不匹配。
    public static func score(query: String, snippet: Snippet) -> Double? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        if !snippet.keyword.isEmpty, snippet.keyword.compare(q, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame { return 1.0 }
        var best: Double?
        let py = Pinyin.convert(snippet.title)
        if let s = FuzzyMatcher.score(query: q, candidate: snippet.title, pinyinFull: py.hasCJK ? py.full : nil, pinyinInitials: py.hasCJK ? py.initials : nil) { best = s * 0.95 }
        if !snippet.keyword.isEmpty, let s = FuzzyMatcher.score(query: q, candidate: snippet.keyword) { best = max(best ?? 0, s * 0.9) }
        if snippet.content.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { best = max(best ?? 0, 0.5) }
        return best
    }

    public static func useBoost(_ count: Int) -> Double { min(0.05, log(Double(count) + 1) * 0.01) }
}
