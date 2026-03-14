import Foundation
import GRDB

/// Store for Layer 5: Values & Priorities (value_traits).
final class Layer5Store: @unchecked Sendable {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    func upsertTrait(_ trait: ValueTrait) throws {
        try db.write { db in try trait.save(db) }
    }

    func fetchTraits(dimension: String? = nil) throws -> [ValueTrait] {
        try db.read { db in
            var request = ValueTrait.all()
            if let dimension {
                request = request.filter(ValueTrait.Columns.dimension == dimension)
            }
            return try request.fetchAll(db)
        }
    }

    func fetchTrait(id: String) throws -> ValueTrait? {
        try db.read { db in try ValueTrait.fetchOne(db, key: id) }
    }

    func traitCount() throws -> Int {
        try db.read { db in try ValueTrait.fetchCount(db) }
    }

    func deleteAll() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM value_traits")
        }
    }
}
