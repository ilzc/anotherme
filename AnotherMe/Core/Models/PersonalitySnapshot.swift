import Foundation
import GRDB

/// A point-in-time snapshot of the user's full personality profile.
struct PersonalitySnapshot: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "personality_snapshots"

    var id: String
    var snapshotDate: Date
    var fullProfile: String        // JSON
    var summaryText: String?
    var trigger: String            // daily / weekly / threshold

    init(
        id: String = UUID().uuidString,
        snapshotDate: Date = .now,
        fullProfile: String,
        summaryText: String? = nil,
        trigger: String
    ) {
        self.id = id
        self.snapshotDate = snapshotDate
        self.fullProfile = fullProfile
        self.summaryText = summaryText
        self.trigger = trigger
    }

    enum Columns: String, ColumnExpression {
        case id, snapshotDate, fullProfile, summaryText, trigger
    }
}
