import Foundation
import GRDB

/// Store for Layer 1: Behavioral Rhythms (daily_rhythms + rhythm_traits).
final class Layer1Store: @unchecked Sendable {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    // MARK: - Daily Rhythms

    func insertRhythm(_ rhythm: DailyRhythm) throws {
        try db.write { db in try rhythm.save(db) }
    }

    func fetchRhythm(for date: Date) throws -> DailyRhythm? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return try db.read { db in
            try DailyRhythm
                .filter(DailyRhythm.Columns.date == startOfDay)
                .fetchOne(db)
        }
    }

    func fetchRhythms(from: Date, to: Date) throws -> [DailyRhythm] {
        try db.read { db in
            try DailyRhythm
                .filter(DailyRhythm.Columns.date >= from)
                .filter(DailyRhythm.Columns.date < to)
                .order(DailyRhythm.Columns.date.asc)
                .fetchAll(db)
        }
    }

    func fetchRecentRhythms(limit: Int = 30) throws -> [DailyRhythm] {
        try db.read { db in
            try DailyRhythm
                .order(DailyRhythm.Columns.date.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Rhythm Traits

    func upsertTrait(_ trait: RhythmTrait) throws {
        try db.write { db in try trait.save(db) }
    }

    func fetchTraits(dimension: String? = nil) throws -> [RhythmTrait] {
        try db.read { db in
            var request = RhythmTrait.all()
            if let dimension {
                request = request.filter(RhythmTrait.Columns.dimension == dimension)
            }
            return try request.fetchAll(db)
        }
    }

    func fetchTrait(id: String) throws -> RhythmTrait? {
        try db.read { db in try RhythmTrait.fetchOne(db, key: id) }
    }

    func rhythmCount() throws -> Int {
        try db.read { db in try DailyRhythm.fetchCount(db) }
    }

    func deleteAll() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM daily_rhythms")
            try db.execute(sql: "DELETE FROM rhythm_traits")
        }
    }
}
