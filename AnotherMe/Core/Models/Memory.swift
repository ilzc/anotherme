import Foundation
import GRDB

struct Memory: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "memories"

    var id: String
    var content: String           // e.g. "User is researching Core ML model optimization"
    var category: String          // topic / intent / habit / opinion / milestone
    var keywords: String          // JSON array: ["CoreML", "ML"]
    var embedding: Data?          // Optional embedding vector
    var importance: Double        // 0.0~1.0
    var accessCount: Int          // Times recalled in chat
    var pinned: Bool              // Personality-type memories don't decay
    var sourceType: String        // activity / insight / chat / consolidation
    var sourceId: String?         // Associated record ID
    var isConsolidated: Bool      // Whether this memory is a consolidation product
    var createdAt: Date
    var lastAccessedAt: Date

    init(
        id: String = UUID().uuidString,
        content: String,
        category: String,
        keywords: String = "[]",
        embedding: Data? = nil,
        importance: Double = 0.5,
        accessCount: Int = 0,
        pinned: Bool = false,
        sourceType: String,
        sourceId: String? = nil,
        isConsolidated: Bool = false,
        createdAt: Date = .now,
        lastAccessedAt: Date = .now
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.keywords = keywords
        self.embedding = embedding
        self.importance = importance
        self.accessCount = accessCount
        self.pinned = pinned
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.isConsolidated = isConsolidated
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }

    var parsedKeywords: [String] {
        guard let data = keywords.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    enum Columns: String, ColumnExpression {
        case id, content, category, keywords, embedding
        case importance, accessCount, pinned
        case sourceType, sourceId, isConsolidated, createdAt, lastAccessedAt
    }
}
