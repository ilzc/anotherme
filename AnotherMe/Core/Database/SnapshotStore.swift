import Foundation
import GRDB

/// Store for personality snapshots.
final class SnapshotStore: @unchecked Sendable {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    func insert(_ snapshot: PersonalitySnapshot) throws {
        try db.write { db in try snapshot.insert(db) }
    }

    func fetchLatest() throws -> PersonalitySnapshot? {
        try db.read { db in
            try PersonalitySnapshot
                .order(PersonalitySnapshot.Columns.snapshotDate.desc)
                .fetchOne(db)
        }
    }

    func fetchAll(limit: Int = 100) throws -> [PersonalitySnapshot] {
        try db.read { db in
            try PersonalitySnapshot
                .order(PersonalitySnapshot.Columns.snapshotDate.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchByTrigger(_ trigger: String, limit: Int = 30) throws -> [PersonalitySnapshot] {
        try db.read { db in
            try PersonalitySnapshot
                .filter(PersonalitySnapshot.Columns.trigger == trigger)
                .order(PersonalitySnapshot.Columns.snapshotDate.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func snapshotCount() throws -> Int {
        try db.read { db in try PersonalitySnapshot.fetchCount(db) }
    }

    func deleteAll() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM personality_snapshots")
        }
    }

    // MARK: - MBTI Results

    func insertMBTI(_ result: MBTIResult) throws {
        try db.write { db in try result.insert(db) }
    }

    func fetchLatestMBTI() throws -> MBTIResult? {
        try db.read { db in
            try MBTIResult
                .order(MBTIResult.Columns.analysisDate.desc)
                .fetchOne(db)
        }
    }

    func fetchAllMBTI(limit: Int = 20) throws -> [MBTIResult] {
        try db.read { db in
            try MBTIResult
                .order(MBTIResult.Columns.analysisDate.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Big Five Results

    func insertBigFive(_ result: BigFiveResult) throws {
        try db.write { db in try result.insert(db) }
    }

    func fetchLatestBigFive() throws -> BigFiveResult? {
        try db.read { db in
            try BigFiveResult
                .order(BigFiveResult.Columns.analysisDate.desc)
                .fetchOne(db)
        }
    }

    func fetchAllBigFive(limit: Int = 20) throws -> [BigFiveResult] {
        try db.read { db in
            try BigFiveResult
                .order(BigFiveResult.Columns.analysisDate.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
