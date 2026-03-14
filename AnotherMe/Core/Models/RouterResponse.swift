import Foundation

struct RouterResponse: Codable, Sendable {
    let intent: Intent
    let layersNeeded: [Int]
    let timeRange: String  // "today" / "last_7_days" / "last_30_days" / "all"
    let queryType: String  // Chinese classification label
    let specificQueries: [LayerQuery]
    let needActivityLogs: Bool
    let needKnowledgeGraph: Bool
    let formatHint: String?

    enum Intent: String, Codable, Sendable {
        case memoryRecall = "memory_recall"
        case selfAwareness = "self_awareness"
        case decisionSupport = "decision_support"
        case ghostwriting = "ghostwriting"
        case associationDiscovery = "association_discovery"
        case prediction = "prediction"
    }

    struct LayerQuery: Codable, Sendable {
        let layer: Int
        let dimensions: [String]
    }

    enum CodingKeys: String, CodingKey {
        case intent
        case layersNeeded = "layers_needed"
        case timeRange = "time_range"
        case queryType = "query_type"
        case specificQueries = "specific_queries"
        case needActivityLogs = "need_activity_logs"
        case needKnowledgeGraph = "need_knowledge_graph"
        case formatHint = "format_hint"
    }
}
