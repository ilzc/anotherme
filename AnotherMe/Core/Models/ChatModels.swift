import Foundation
import GRDB

/// A conversation session with the Agent.
struct ChatSession: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "chat_sessions"

    var id: String
    var createdAt: Date
    var title: String

    init(
        id: String = UUID().uuidString,
        createdAt: Date = .now,
        title: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
    }

    enum Columns: String, ColumnExpression {
        case id, createdAt, title
    }
}

/// A single message in a chat session.
struct ChatMessage: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "chat_messages"

    var id: String
    var sessionId: String
    var timestamp: Date
    var role: String               // user / agent
    var content: String
    var referencedLayers: [Int]    // JSON array
    var referencedData: [String: String] // JSON dict

    init(
        id: String = UUID().uuidString,
        sessionId: String,
        timestamp: Date = .now,
        role: String,
        content: String,
        referencedLayers: [Int] = [],
        referencedData: [String: String] = [:]
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.role = role
        self.content = content
        self.referencedLayers = referencedLayers
        self.referencedData = referencedData
    }

    enum Columns: String, ColumnExpression {
        case id, sessionId, timestamp, role, content
        case referencedLayers, referencedData
    }

    enum CodingKeys: String, CodingKey {
        case id, sessionId, timestamp, role, content
        case referencedLayers, referencedData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        role = try c.decode(String.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)

        let layersStr = try c.decode(String.self, forKey: .referencedLayers)
        if let data = layersStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Int].self, from: data) {
            referencedLayers = decoded
        } else {
            referencedLayers = []
        }

        let dataStr = try c.decode(String.self, forKey: .referencedData)
        if let data = dataStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            referencedData = decoded
        } else {
            referencedData = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)

        let layersData = try JSONEncoder().encode(referencedLayers)
        try c.encode(String(data: layersData, encoding: .utf8) ?? "[]", forKey: .referencedLayers)

        let refData = try JSONEncoder().encode(referencedData)
        try c.encode(String(data: refData, encoding: .utf8) ?? "{}", forKey: .referencedData)
    }
}
