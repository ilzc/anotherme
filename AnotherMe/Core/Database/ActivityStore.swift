import Foundation
import GRDB

final class ActivityStore: @unchecked Sendable {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    // MARK: - Write

    func insert(_ record: ActivityRecord) throws {
        try db.write { db in
            try record.insert(db)
        }
    }

    func markAnalyzed(ids: [UUID]) throws {
        try db.write { db in
            let idStrings = ids.map { $0.uuidString }
            try db.execute(
                sql: "UPDATE activity_logs SET analyzed = 1 WHERE id IN (\(idStrings.map { _ in "?" }.joined(separator: ",")))",
                arguments: StatementArguments(idStrings)
            )
        }
    }

    // MARK: - Read

    func fetchToday() throws -> [ActivityRecord] {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return try db.read { db in
            try ActivityRecord
                .filter(ActivityRecord.Columns.timestamp >= startOfDay)
                .order(ActivityRecord.Columns.timestamp.asc)
                .fetchAll(db)
        }
    }

    func fetch(from: Date, to: Date) throws -> [ActivityRecord] {
        try db.read { db in
            try ActivityRecord
                .filter(ActivityRecord.Columns.timestamp >= from)
                .filter(ActivityRecord.Columns.timestamp < to)
                .order(ActivityRecord.Columns.timestamp.asc)
                .fetchAll(db)
        }
    }

    func fetchUnanalyzed(limit: Int = 200) throws -> [ActivityRecord] {
        try db.read { db in
            try ActivityRecord
                .filter(ActivityRecord.Columns.analyzed == false)
                .order(ActivityRecord.Columns.timestamp.asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchTodayAppDistribution() throws -> [(appName: String, count: Int)] {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT appName, COUNT(*) as cnt
                FROM activity_logs
                WHERE timestamp >= ?
                GROUP BY appName
                ORDER BY cnt DESC
                """, arguments: [startOfDay])
            return rows.map { ($0["appName"], $0["cnt"]) }
        }
    }

    func fetchTodayCategoryDistribution() throws -> [(category: String, count: Int)] {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT activityCategory, COUNT(*) as cnt
                FROM activity_logs
                WHERE timestamp >= ?
                GROUP BY activityCategory
                ORDER BY cnt DESC
                """, arguments: [startOfDay])
            return rows.map { ($0["activityCategory"], $0["cnt"]) }
        }
    }

    func totalCount() throws -> Int {
        try db.read { db in
            try ActivityRecord.fetchCount(db)
        }
    }

    // MARK: - Cleanup

    func deleteAll() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM activity_logs")
        }
    }

    func resetAnalyzedFlags() throws {
        try db.write { db in
            try db.execute(sql: "UPDATE activity_logs SET analyzed = 0")
        }
    }

    func pruneOldRecords(olderThanDays days: Int = 90) throws {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) else {
            return
        }
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM activity_logs WHERE timestamp < ?",
                arguments: [cutoff]
            )
        }
    }
}
