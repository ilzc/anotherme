import Foundation
import GRDB

/// Store for insights.
final class InsightStore: @unchecked Sendable {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    func insert(_ insight: Insight) throws {
        try db.write { db in try insight.insert(db) }
    }

    func fetchRecent(limit: Int = 50) throws -> [Insight] {
        try db.read { db in
            try Insight
                .order(Insight.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchUnnotified() throws -> [Insight] {
        try db.read { db in
            try Insight
                .filter(Insight.Columns.notified == false)
                .order(Insight.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func fetchByType(_ type: String, limit: Int = 30) throws -> [Insight] {
        try db.read { db in
            try Insight
                .filter(Insight.Columns.type == type)
                .order(Insight.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func markNotified(ids: [String]) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE insights SET notified = 1 WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))",
                arguments: StatementArguments(ids)
            )
        }
    }

    func insightCount() throws -> Int {
        try db.read { db in try Insight.fetchCount(db) }
    }

    func deleteAll() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM insights")
        }
    }
}
