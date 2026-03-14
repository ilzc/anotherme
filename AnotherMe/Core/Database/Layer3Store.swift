import Foundation
import GRDB

/// Store for Layer 3: Cognitive Style (cognitive_traits + problem_solving_sequences).
final class Layer3Store: @unchecked Sendable {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    // MARK: - Cognitive Traits

    func upsertTrait(_ trait: CognitiveTrait) throws {
        try db.write { db in try trait.save(db) }
    }

    func fetchTraits(dimension: String? = nil) throws -> [CognitiveTrait] {
        try db.read { db in
            var request = CognitiveTrait.all()
            if let dimension {
                request = request.filter(CognitiveTrait.Columns.dimension == dimension)
            }
            return try request.fetchAll(db)
        }
    }

    func fetchTrait(id: String) throws -> CognitiveTrait? {
        try db.read { db in try CognitiveTrait.fetchOne(db, key: id) }
    }

    // MARK: - Problem Solving Sequences

    func insertSequence(_ seq: ProblemSolvingSequence) throws {
        try db.write { db in try seq.insert(db) }
    }

    func fetchRecentSequences(limit: Int = 50) throws -> [ProblemSolvingSequence] {
        try db.read { db in
            try ProblemSolvingSequence
                .order(ProblemSolvingSequence.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchSequences(from: Date, to: Date) throws -> [ProblemSolvingSequence] {
        try db.read { db in
            try ProblemSolvingSequence
                .filter(ProblemSolvingSequence.Columns.timestamp >= from)
                .filter(ProblemSolvingSequence.Columns.timestamp < to)
                .order(ProblemSolvingSequence.Columns.timestamp.asc)
                .fetchAll(db)
        }
    }

    func sequenceCount() throws -> Int {
        try db.read { db in try ProblemSolvingSequence.fetchCount(db) }
    }

    func deleteAll() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM cognitive_traits")
            try db.execute(sql: "DELETE FROM problem_solving_sequences")
        }
    }
}
