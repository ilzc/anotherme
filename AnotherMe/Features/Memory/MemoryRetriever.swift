import Foundation

/// Retrieves relevant memories for chat context injection.
/// Uses embedding similarity when available, falls back to full injection.
struct MemoryRetriever {
    let memoryStore: MemoryStore

    /// Recall relevant memories for the given query.
    /// Tries keyword search first (always available). Returns empty if no relevant match found.
    func recall(query: String, limit: Int = 5) throws -> [Memory] {
        // 1. Try keyword search first (always available, no AI dependency)
        let keywords = extractKeywords(from: query)
        if !keywords.isEmpty {
            let results = try memoryStore.searchByKeywords(keywords, limit: limit * 2)
            if !results.isEmpty {
                // Re-rank by recency-weighted importance
                let ranked = Self.rankByRecency(results).prefix(limit)
                for memory in ranked {
                    try? memoryStore.incrementAccess(id: memory.id)
                }
                return Array(ranked)
            }
        }

        // 2. TODO: If embedding endpoint configured, try vector similarity search
        // let embeddingSlot = AIModelSlotStore.shared.load(name: "embedding")
        // if embeddingSlot.isConfigured { ... }

        // 3. No relevant match — return empty rather than dumping all memories
        return []
    }

    /// Re-ranks memories by composite score: importance * recency decay.
    /// Recent memories are preferred; old memories need higher importance to surface.
    private static func rankByRecency(_ memories: [Memory]) -> [Memory] {
        memories.sorted { a, b in
            recencyScore(a) > recencyScore(b)
        }
    }

    private static func recencyScore(_ memory: Memory) -> Double {
        let daysSince = Date.now.timeIntervalSince(memory.createdAt) / 86400.0
        let recencyFactor = 1.0 / (1.0 + daysSince / 7.0)
        return memory.importance * recencyFactor
    }

    /// Format memories as text for prompt injection.
    /// Uses relative time and first-person perspective, no internal labels.
    static func formatMemories(_ memories: [Memory]) -> String? {
        guard !memories.isEmpty else { return nil }
        return memories.map { memory in
            let timeAgo = memory.createdAt.relativeTimeString
            return "- (\(timeAgo)) \(memory.content)"
        }.joined(separator: "\n")
    }


    /// Simple keyword extraction from user query.
    private func extractKeywords(from text: String) -> [String] {
        // Split by common delimiters and filter short/common words
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        return Array(words.prefix(5))
    }
}
