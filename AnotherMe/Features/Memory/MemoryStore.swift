import Foundation
import GRDB

final class MemoryStore: @unchecked Sendable {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    func insert(_ memory: Memory) throws {
        try db.write { db in
            try memory.insert(db)
        }
    }

    func update(_ memory: Memory) throws {
        try db.write { db in
            try memory.update(db)
        }
    }

    func fetchAll(limit: Int = 300) throws -> [Memory] {
        try db.read { db in
            try Memory
                .order(Memory.Columns.importance.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchRecent(limit: Int = 10) throws -> [Memory] {
        try db.read { db in
            try Memory
                .order(Memory.Columns.lastAccessedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func searchByKeywords(_ keywords: [String], limit: Int = 5) throws -> [Memory] {
        try db.read { db in
            // Simple keyword containment search in the keywords JSON column
            var allResults: [Memory] = []
            for keyword in keywords {
                let pattern = "%\(keyword)%"
                let results = try Memory
                    .filter(Memory.Columns.keywords.like(pattern))
                    .limit(limit)
                    .fetchAll(db)
                allResults.append(contentsOf: results)
            }
            // Deduplicate by id, keep highest importance
            let unique = Dictionary(grouping: allResults, by: \.id)
                .values
                .compactMap { $0.max(by: { $0.importance < $1.importance }) }
                .sorted { $0.importance > $1.importance }
            return Array(unique.prefix(limit))
        }
    }

    func searchByEmbedding(_ vector: [Float], limit: Int = 5) throws -> [Memory] {
        // Load all memories with embeddings, compute cosine similarity in-memory
        // 300 x 1536 dim ~ 1.8MB -- acceptable for in-memory computation
        let all = try db.read { db in
            try Memory
                .filter(Memory.Columns.embedding != nil)
                .fetchAll(db)
        }

        let ranked = all.compactMap { memory -> (Memory, Float)? in
            guard let embData = memory.embedding else { return nil }
            let embVector = embData.withUnsafeBytes { buf in
                Array(buf.bindMemory(to: Float.self))
            }
            guard embVector.count == vector.count else { return nil }
            let similarity = cosineSimilarity(vector, embVector)
            return (memory, similarity)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)

        return Array(ranked)
    }

    func incrementAccess(id: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                UPDATE memories SET accessCount = accessCount + 1, lastAccessedAt = ? WHERE id = ?
                """,
                arguments: [Date.now, id]
            )
        }
    }

    func insertOrMerge(_ memory: Memory) throws {
        let existing = try searchByKeywords(memory.parsedKeywords, limit: 3)
        if let match = existing.first(where: { keywordOverlap($0, memory) > 0.5 }) {
            var updated = match
            updated.content = memory.content
            updated.importance = max(match.importance, memory.importance)
            updated.lastAccessedAt = .now
            try update(updated)
        } else {
            try insert(memory)
        }
    }

    func totalCount() throws -> Int {
        try db.read { db in
            try Memory.fetchCount(db)
        }
    }

    // MARK: - CRUD for UI

    func fetchByCategory(_ category: String, limit: Int = 50) throws -> [Memory] {
        try db.read { db in
            try Memory
                .filter(Memory.Columns.category == category)
                .order(Memory.Columns.importance.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchTodayCount() throws -> Int {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return try db.read { db in
            try Memory
                .filter(Memory.Columns.createdAt >= startOfDay)
                .fetchCount(db)
        }
    }

    func delete(id: String) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM memories WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func togglePin(id: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                UPDATE memories SET pinned = NOT pinned WHERE id = ?
                """,
                arguments: [id]
            )
        }
    }

    func updateImportance(id: String, importance: Double) throws {
        try db.write { db in
            try db.execute(
                sql: """
                UPDATE memories SET importance = ? WHERE id = ?
                """,
                arguments: [importance, id]
            )
        }
    }

    func consolidatedCount() throws -> Int {
        try db.read { db in
            try Memory
                .filter(Memory.Columns.isConsolidated == true)
                .fetchCount(db)
        }
    }

    // MARK: - Lifecycle

    func decayUnaccessed(daysSince: Int = 30, factor: Double = 0.9) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysSince, to: .now) ?? .now
        try db.write { db in
            try db.execute(
                sql: """
                UPDATE memories
                SET importance = importance * ?
                WHERE lastAccessedAt < ? AND pinned = 0 AND importance < 0.8
                """,
                arguments: [factor, cutoff]
            )
        }
    }

    /// Fetch low-scoring, non-protected memories that are candidates for consolidation or deletion.
    /// Protected: pinned, importance >= 0.8, or already consolidated.
    /// - Parameter skipRecencyCheck: When true, ignores the 14-day recency window (for debug).
    func fetchConsolidationCandidates(keepTop: Int = 300, skipRecencyCheck: Bool = false) throws -> [Memory] {
        let count = try totalCount()
        guard count > keepTop else { return [] }

        return try db.read { db in
            var query = Memory
                .filter(Memory.Columns.pinned == false)
                .filter(Memory.Columns.importance < 0.8)
                .filter(Memory.Columns.isConsolidated == false)

            if !skipRecencyCheck {
                let recentCutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
                query = query.filter(Memory.Columns.createdAt < recentCutoff)
            }

            return try query
                .order(sql: "importance * (1.0 / (1.0 + (julianday('now') - julianday(lastAccessedAt)) / 30.0)) ASC")
                .limit(count - keepTop)
                .fetchAll(db)
        }
    }

    /// Fetch ALL non-protected, non-consolidated memories regardless of count threshold.
    /// Used for debug/force consolidation.
    func fetchAllConsolidationCandidates() throws -> [Memory] {
        try db.read { db in
            try Memory
                .filter(Memory.Columns.pinned == false)
                .filter(Memory.Columns.importance < 0.8)
                .filter(Memory.Columns.isConsolidated == false)
                .order(sql: "importance * (1.0 / (1.0 + (julianday('now') - julianday(lastAccessedAt)) / 30.0)) ASC")
                .fetchAll(db)
        }
    }

    func pruneByImportance(keepTop: Int = 300) throws {
        let count = try totalCount()
        guard count > keepTop else { return }
        try db.write { db in
            // Delete lowest-scoring non-protected memories.
            // Protected: pinned or importance >= 0.8.
            try db.execute(
                sql: """
                DELETE FROM memories WHERE id IN (
                    SELECT id FROM memories
                    WHERE pinned = 0 AND importance < 0.8
                    ORDER BY importance * (1.0 / (1.0 + (julianday('now') - julianday(lastAccessedAt)) / 30.0)) ASC
                    LIMIT ?
                )
                """,
                arguments: [count - keepTop]
            )
        }
    }

    func deleteByIDs(_ ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try db.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM memories WHERE id IN (\(placeholders))",
                arguments: StatementArguments(ids)
            )
        }
    }

    /// Atomically replace a set of memories with consolidated summaries.
    /// Both insert and delete happen in a single transaction to prevent duplicates on crash.
    func replaceWithConsolidated(deleteIDs: [String], insert newMemories: [Memory]) throws {
        guard !deleteIDs.isEmpty, !newMemories.isEmpty else { return }
        try db.write { db in
            for memory in newMemories {
                try memory.insert(db)
            }
            let placeholders = deleteIDs.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM memories WHERE id IN (\(placeholders))",
                arguments: StatementArguments(deleteIDs)
            )
        }
    }

    // MARK: - Helpers

    private func keywordOverlap(_ a: Memory, _ b: Memory) -> Double {
        let setA = Set(a.parsedKeywords.map { $0.lowercased() })
        let setB = Set(b.parsedKeywords.map { $0.lowercased() })
        guard !setA.isEmpty || !setB.isEmpty else { return 0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}
