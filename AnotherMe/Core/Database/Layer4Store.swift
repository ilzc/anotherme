import Foundation
import GRDB

/// Store for Layer 4: Communication Persona (expression_traits + writing_samples).
final class Layer4Store: @unchecked Sendable {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    // MARK: - Expression Traits

    func upsertTrait(_ trait: ExpressionTrait) throws {
        try db.write { db in try trait.save(db) }
    }

    func fetchTraits(dimension: String? = nil) throws -> [ExpressionTrait] {
        try db.read { db in
            var request = ExpressionTrait.all()
            if let dimension {
                request = request.filter(ExpressionTrait.Columns.dimension == dimension)
            }
            return try request.fetchAll(db)
        }
    }

    // MARK: - Writing Samples

    func insertSample(_ sample: WritingSample) throws {
        try db.write { db in try sample.insert(db) }
    }

    func fetchRecentSamples(limit: Int = 50) throws -> [WritingSample] {
        try db.read { db in
            try WritingSample
                .order(WritingSample.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchSamples(context: String, limit: Int = 50) throws -> [WritingSample] {
        try db.read { db in
            try WritingSample
                .filter(WritingSample.Columns.context == context)
                .order(WritingSample.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func sampleCount() throws -> Int {
        try db.read { db in try WritingSample.fetchCount(db) }
    }

    func deleteAll() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM expression_traits")
            try db.execute(sql: "DELETE FROM writing_samples")
        }
    }
}
