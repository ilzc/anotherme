import Foundation
import GRDB

/// Store for Layer 2: Knowledge Graph (knowledge_nodes + knowledge_edges + knowledge_traits).
final class Layer2Store: @unchecked Sendable {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    // MARK: - Knowledge Nodes

    func upsertNode(_ node: KnowledgeNode) throws {
        try db.write { db in try node.save(db) }
    }

    func fetchNode(byTopic topic: String) throws -> KnowledgeNode? {
        try db.read { db in
            try KnowledgeNode
                .filter(KnowledgeNode.Columns.topic == topic)
                .fetchOne(db)
        }
    }

    func fetchTopNodes(limit: Int = 20) throws -> [KnowledgeNode] {
        try db.read { db in
            try KnowledgeNode
                .order(KnowledgeNode.Columns.totalTimeSpent.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchRecentNodes(limit: Int = 20) throws -> [KnowledgeNode] {
        try db.read { db in
            try KnowledgeNode
                .order(KnowledgeNode.Columns.lastSeen.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchAllNodes() throws -> [KnowledgeNode] {
        try db.read { db in try KnowledgeNode.fetchAll(db) }
    }

    func nodeCount() throws -> Int {
        try db.read { db in try KnowledgeNode.fetchCount(db) }
    }

    // MARK: - Knowledge Edges

    func upsertEdge(_ edge: KnowledgeEdge) throws {
        try db.write { db in try edge.save(db) }
    }

    func fetchEdges(forNodeId nodeId: String) throws -> [KnowledgeEdge] {
        try db.read { db in
            try KnowledgeEdge
                .filter(KnowledgeEdge.Columns.sourceNodeId == nodeId ||
                        KnowledgeEdge.Columns.targetNodeId == nodeId)
                .order(KnowledgeEdge.Columns.strength.desc)
                .fetchAll(db)
        }
    }

    func fetchEdge(source: String, target: String) throws -> KnowledgeEdge? {
        try db.read { db in
            try KnowledgeEdge
                .filter(KnowledgeEdge.Columns.sourceNodeId == source &&
                        KnowledgeEdge.Columns.targetNodeId == target)
                .fetchOne(db)
        }
    }

    func fetchStrongestEdges(limit: Int = 50) throws -> [KnowledgeEdge] {
        try db.read { db in
            try KnowledgeEdge
                .order(KnowledgeEdge.Columns.strength.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Knowledge Traits

    func upsertTrait(_ trait: KnowledgeTrait) throws {
        try db.write { db in try trait.save(db) }
    }

    func fetchTraits(dimension: String? = nil) throws -> [KnowledgeTrait] {
        try db.read { db in
            var request = KnowledgeTrait.all()
            if let dimension {
                request = request.filter(KnowledgeTrait.Columns.dimension == dimension)
            }
            return try request.fetchAll(db)
        }
    }

    func deleteAll() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM knowledge_nodes")
            try db.execute(sql: "DELETE FROM knowledge_edges")
            try db.execute(sql: "DELETE FROM knowledge_traits")
        }
    }
}
