import Foundation
import GRDB

public nonisolated struct Conversation: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "conversation"
    public var id: String
    public var title: String
    public var providerID: String?
    public var model: String?
    public var createdAt: Double
    public var updatedAt: Double
}

public nonisolated enum MessageStatus: String, Codable, Sendable { case streaming, done, error }

public nonisolated struct StoredMessage: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "message"
    public var id: String
    public var conversationID: String
    public var role: String
    public var content: String
    public var reasoning: String
    public var status: String
    public var errorText: String?
    public var createdAt: Double

    public var messageStatus: MessageStatus { MessageStatus(rawValue: status) ?? .done }
}

public nonisolated final class ChatStore: Sendable {
    let queue: DatabaseQueue

    public init(path: String? = nil) throws {
        queue = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "conversation") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("providerID", .text)
                t.column("model", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull().indexed()
            }
            try db.create(table: "message") { t in
                t.column("id", .text).primaryKey()
                t.column("conversationID", .text).notNull().indexed().references("conversation", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("reasoning", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull().defaults(to: "done")
                t.column("errorText", .text)
                t.column("createdAt", .double).notNull()
            }
        }
        try m.migrate(queue)
        // 上次异常退出时遗留的“生成中”消息标记为完成
        try queue.write { try $0.execute(sql: "UPDATE message SET status = 'done' WHERE status = 'streaming'") }
    }

    public static func title(from text: String) -> String {
        let t = text.split(whereSeparator: { $0.isNewline }).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return t.count > 30 ? String(t.prefix(30)) : (t.isEmpty ? "新对话" : t)
    }

    @discardableResult
    public func createConversation(title: String, providerID: String?, model: String?, now: Date = Date()) throws -> Conversation {
        let c = Conversation(id: UUID().uuidString, title: title, providerID: providerID, model: model, createdAt: now.timeIntervalSince1970, updatedAt: now.timeIntervalSince1970)
        try queue.write { try c.insert($0) }
        return c
    }

    public func conversations(limit: Int = 100) throws -> [Conversation] {
        try queue.read { try Conversation.order(Column("updatedAt").desc).limit(limit).fetchAll($0) }
    }

    public func conversation(id: String) throws -> Conversation? { try queue.read { try Conversation.fetchOne($0, key: id) } }

    public func latestConversation() throws -> Conversation? { try conversations(limit: 1).first }

    public func touch(_ id: String, model: String?, providerID: String?, now: Date = Date()) throws {
        try queue.write {
            try $0.execute(sql: "UPDATE conversation SET updatedAt = ?, model = COALESCE(?, model), providerID = COALESCE(?, providerID) WHERE id = ?",
                           arguments: [now.timeIntervalSince1970, model, providerID, id])
        }
    }

    public func deleteConversation(id: String) throws { _ = try queue.write { try Conversation.deleteOne($0, key: id) } }

    public func messages(in conversationID: String) throws -> [StoredMessage] {
        try queue.read { try StoredMessage.filter(Column("conversationID") == conversationID).order(sql: "rowid ASC").fetchAll($0) }
    }

    @discardableResult
    public func addMessage(conversationID: String, role: String, content: String, status: MessageStatus = .done, now: Date = Date()) throws -> StoredMessage {
        let m = StoredMessage(id: UUID().uuidString, conversationID: conversationID, role: role, content: content, reasoning: "", status: status.rawValue, errorText: nil, createdAt: now.timeIntervalSince1970)
        try queue.write { try m.insert($0) }
        return m
    }

    public func update(messageID: String, content: String, reasoning: String, status: MessageStatus, errorText: String? = nil) throws {
        try queue.write {
            try $0.execute(sql: "UPDATE message SET content = ?, reasoning = ?, status = ?, errorText = ? WHERE id = ?",
                           arguments: [content, reasoning, status.rawValue, errorText, messageID])
        }
    }

    public func deleteMessage(id: String) throws { _ = try queue.write { try StoredMessage.deleteOne($0, key: id) } }
}
