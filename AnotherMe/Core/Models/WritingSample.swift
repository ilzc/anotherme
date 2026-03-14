import Foundation
import GRDB

/// Layer 4: A sample of the user's writing for communication style analysis.
struct WritingSample: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "writing_samples"

    var id: String
    var timestamp: Date
    var context: String            // work_chat, email, code_comment, etc.
    var content: String
    var sentiment: String?
    var wordCount: Int

    init(
        id: String = UUID().uuidString,
        timestamp: Date = .now,
        context: String,
        content: String,
        sentiment: String? = nil,
        wordCount: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.context = context
        self.content = content
        self.sentiment = sentiment
        self.wordCount = wordCount
    }

    enum Columns: String, ColumnExpression {
        case id, timestamp, context, content, sentiment, wordCount
    }
}
