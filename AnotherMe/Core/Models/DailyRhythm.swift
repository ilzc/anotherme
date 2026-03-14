import Foundation
import GRDB

/// Layer 1: A single day's behavioral rhythm summary.
struct DailyRhythm: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "daily_rhythms"

    var id: String
    var date: Date
    var activeStart: String?          // HH:mm
    var activeEnd: String?            // HH:mm
    var totalActiveMins: Int
    var appDistribution: [String: Int] // JSON dict in SQLite
    var switchCount: Int
    var focusScore: Double
    var peakHours: [Int]             // JSON array in SQLite

    init(
        id: String = UUID().uuidString,
        date: Date,
        activeStart: String? = nil,
        activeEnd: String? = nil,
        totalActiveMins: Int = 0,
        appDistribution: [String: Int] = [:],
        switchCount: Int = 0,
        focusScore: Double = 0,
        peakHours: [Int] = []
    ) {
        self.id = id
        self.date = date
        self.activeStart = activeStart
        self.activeEnd = activeEnd
        self.totalActiveMins = totalActiveMins
        self.appDistribution = appDistribution
        self.switchCount = switchCount
        self.focusScore = focusScore
        self.peakHours = peakHours
    }

    // MARK: - Columns

    enum Columns: String, ColumnExpression {
        case id, date, activeStart, activeEnd, totalActiveMins
        case appDistribution, switchCount, focusScore, peakHours
    }

    // MARK: - Custom Codable for JSON fields

    enum CodingKeys: String, CodingKey {
        case id, date, activeStart, activeEnd, totalActiveMins
        case appDistribution, switchCount, focusScore, peakHours
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        activeStart = try c.decodeIfPresent(String.self, forKey: .activeStart)
        activeEnd = try c.decodeIfPresent(String.self, forKey: .activeEnd)
        totalActiveMins = try c.decode(Int.self, forKey: .totalActiveMins)
        switchCount = try c.decode(Int.self, forKey: .switchCount)
        focusScore = try c.decode(Double.self, forKey: .focusScore)

        let distStr = try c.decode(String.self, forKey: .appDistribution)
        if let data = distStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            appDistribution = decoded
        } else {
            appDistribution = [:]
        }

        let peakStr = try c.decode(String.self, forKey: .peakHours)
        if let data = peakStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Int].self, from: data) {
            peakHours = decoded
        } else {
            peakHours = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(activeStart, forKey: .activeStart)
        try c.encodeIfPresent(activeEnd, forKey: .activeEnd)
        try c.encode(totalActiveMins, forKey: .totalActiveMins)
        try c.encode(switchCount, forKey: .switchCount)
        try c.encode(focusScore, forKey: .focusScore)

        let distData = try JSONEncoder().encode(appDistribution)
        try c.encode(String(data: distData, encoding: .utf8) ?? "{}", forKey: .appDistribution)

        let peakData = try JSONEncoder().encode(peakHours)
        try c.encode(String(data: peakData, encoding: .utf8) ?? "[]", forKey: .peakHours)
    }
}
