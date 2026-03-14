import Foundation
import GRDB

/// Layer 2: A topic node in the knowledge graph.
struct KnowledgeNode: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "knowledge_nodes"

    var id: String
    var topic: String
    var category: String
    var totalTimeSpent: Int       // seconds
    var visitCount: Int
    var depthScore: Double
    var firstSeen: Date
    var lastSeen: Date

    init(
        id: String = UUID().uuidString,
        topic: String,
        category: String = "other",
        totalTimeSpent: Int = 0,
        visitCount: Int = 0,
        depthScore: Double = 0,
        firstSeen: Date = .now,
        lastSeen: Date = .now
    ) {
        self.id = id
        self.topic = topic
        self.category = category
        self.totalTimeSpent = totalTimeSpent
        self.visitCount = visitCount
        self.depthScore = depthScore
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }

    enum Columns: String, ColumnExpression {
        case id, topic, category, totalTimeSpent
        case visitCount, depthScore, firstSeen, lastSeen
    }
}

/// Layer 2: An edge connecting two knowledge nodes.
struct KnowledgeEdge: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "knowledge_edges"

    var id: String
    var sourceNodeId: String
    var targetNodeId: String
    var coOccurrenceCount: Int
    var strength: Double

    init(
        id: String = UUID().uuidString,
        sourceNodeId: String,
        targetNodeId: String,
        coOccurrenceCount: Int = 0,
        strength: Double = 0
    ) {
        self.id = id
        self.sourceNodeId = sourceNodeId
        self.targetNodeId = targetNodeId
        self.coOccurrenceCount = coOccurrenceCount
        self.strength = strength
    }

    enum Columns: String, ColumnExpression {
        case id, sourceNodeId, targetNodeId, coOccurrenceCount, strength
    }
}
