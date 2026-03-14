import Foundation
import GRDB

struct ActivityRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "activity_logs"

    var id: UUID
    var timestamp: Date
    var appName: String
    var windowTitle: String
    var extractedText: String?
    var contentSummary: String?
    var userIntent: String?
    var activityCategory: String
    var topics: [String]
    var screenIndex: Int
    var captureMode: String
    var analyzed: Bool
    // New structured fields
    var visibleApps: [String]?
    var userAuthored: String?
    var userExpressions: [String]?
    var engagementLevel: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        appName: String,
        windowTitle: String,
        extractedText: String? = nil,
        contentSummary: String? = nil,
        userIntent: String? = nil,
        activityCategory: String = "other",
        topics: [String] = [],
        screenIndex: Int = 0,
        captureMode: CaptureMode,
        analyzed: Bool = false,
        visibleApps: [String]? = nil,
        userAuthored: String? = nil,
        userExpressions: [String]? = nil,
        engagementLevel: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.windowTitle = windowTitle
        self.extractedText = extractedText
        self.contentSummary = contentSummary
        self.userIntent = userIntent
        self.activityCategory = activityCategory
        self.topics = topics
        self.screenIndex = screenIndex
        self.captureMode = captureMode.rawValue
        self.analyzed = analyzed
        self.visibleApps = visibleApps
        self.userAuthored = userAuthored
        self.userExpressions = userExpressions
        self.engagementLevel = engagementLevel
    }

    // MARK: - GRDB Columns

    enum Columns: String, ColumnExpression {
        case id, timestamp, appName, windowTitle, extractedText
        case contentSummary, userIntent, activityCategory, topics
        case screenIndex, captureMode, analyzed
        case visibleApps, userAuthored, userExpressions, engagementLevel
    }

    // MARK: - Custom Codable for array fields (stored as JSON string)

    enum CodingKeys: String, CodingKey {
        case id, timestamp, appName, windowTitle, extractedText
        case contentSummary, userIntent, activityCategory, topics
        case screenIndex, captureMode, analyzed
        case visibleApps, userAuthored, userExpressions, engagementLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        appName = try container.decode(String.self, forKey: .appName)
        windowTitle = try container.decode(String.self, forKey: .windowTitle)
        extractedText = try container.decodeIfPresent(String.self, forKey: .extractedText)
        contentSummary = try container.decodeIfPresent(String.self, forKey: .contentSummary)
        userIntent = try container.decodeIfPresent(String.self, forKey: .userIntent)
        activityCategory = try container.decode(String.self, forKey: .activityCategory)
        screenIndex = try container.decode(Int.self, forKey: .screenIndex)
        captureMode = try container.decode(String.self, forKey: .captureMode)
        analyzed = try container.decode(Bool.self, forKey: .analyzed)
        userAuthored = try container.decodeIfPresent(String.self, forKey: .userAuthored)
        engagementLevel = try container.decodeIfPresent(String.self, forKey: .engagementLevel)

        // userExpressions: stored as JSON string in SQLite
        if let expressionsString = try container.decodeIfPresent(String.self, forKey: .userExpressions),
           let data = expressionsString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            userExpressions = decoded
        } else {
            userExpressions = nil
        }

        // topics: stored as JSON string in SQLite
        let topicsString = try container.decode(String.self, forKey: .topics)
        if let data = topicsString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            topics = decoded
        } else {
            topics = []
        }

        // visibleApps: stored as JSON string in SQLite
        if let appsString = try container.decodeIfPresent(String.self, forKey: .visibleApps),
           let data = appsString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            visibleApps = decoded
        } else {
            visibleApps = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(appName, forKey: .appName)
        try container.encode(windowTitle, forKey: .windowTitle)
        try container.encodeIfPresent(extractedText, forKey: .extractedText)
        try container.encodeIfPresent(contentSummary, forKey: .contentSummary)
        try container.encodeIfPresent(userIntent, forKey: .userIntent)
        try container.encode(activityCategory, forKey: .activityCategory)
        try container.encode(screenIndex, forKey: .screenIndex)
        try container.encode(captureMode, forKey: .captureMode)
        try container.encode(analyzed, forKey: .analyzed)
        try container.encodeIfPresent(userAuthored, forKey: .userAuthored)
        try container.encodeIfPresent(engagementLevel, forKey: .engagementLevel)

        // Encode userExpressions as JSON string
        if let expressions = userExpressions {
            let expressionsData = try JSONEncoder().encode(expressions)
            let expressionsString = String(data: expressionsData, encoding: .utf8) ?? "[]"
            try container.encode(expressionsString, forKey: .userExpressions)
        } else {
            try container.encodeNil(forKey: .userExpressions)
        }

        // Encode topics as JSON string
        let topicsData = try JSONEncoder().encode(topics)
        let topicsString = String(data: topicsData, encoding: .utf8) ?? "[]"
        try container.encode(topicsString, forKey: .topics)

        // Encode visibleApps as JSON string
        if let apps = visibleApps {
            let appsData = try JSONEncoder().encode(apps)
            let appsString = String(data: appsData, encoding: .utf8) ?? "[]"
            try container.encode(appsString, forKey: .visibleApps)
        } else {
            try container.encodeNil(forKey: .visibleApps)
        }
    }
}
