import Foundation
import GRDB

/// Store for chat sessions and messages.
final class ChatStore: @unchecked Sendable {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    // MARK: - Sessions

    func createSession(title: String = "") throws -> ChatSession {
        let session = ChatSession(title: title)
        try db.write { db in try session.insert(db) }
        return session
    }

    func fetchSessions(limit: Int = 50) throws -> [ChatSession] {
        try db.read { db in
            try ChatSession
                .order(ChatSession.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchSession(id: String) throws -> ChatSession? {
        try db.read { db in try ChatSession.fetchOne(db, key: id) }
    }

    func updateSessionTitle(id: String, title: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE chat_sessions SET title = ? WHERE id = ?",
                arguments: [title, id]
            )
        }
    }

    func deleteSession(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM chat_sessions WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Messages

    func insertMessage(_ message: ChatMessage) throws {
        try db.write { db in try message.insert(db) }
    }

    func fetchMessages(sessionId: String) throws -> [ChatMessage] {
        try db.read { db in
            try ChatMessage
                .filter(ChatMessage.Columns.sessionId == sessionId)
                .order(ChatMessage.Columns.timestamp.asc)
                .fetchAll(db)
        }
    }

    func fetchRecentMessages(sessionId: String, limit: Int = 20) throws -> [ChatMessage] {
        try db.read { db in
            try ChatMessage
                .filter(ChatMessage.Columns.sessionId == sessionId)
                .order(ChatMessage.Columns.timestamp.desc)
                .limit(limit)
                .reversed()
                .fetchAll(db)
        }
    }

    func messageCount(sessionId: String) throws -> Int {
        try db.read { db in
            try ChatMessage
                .filter(ChatMessage.Columns.sessionId == sessionId)
                .fetchCount(db)
        }
    }
}
