import Foundation
import GRDB

/// Layer 3: Records a sequence of actions taken during problem solving.
struct ProblemSolvingSequence: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "problem_solving_sequences"

    var id: String
    var timestamp: Date
    var sequence: [String]         // JSON array in SQLite
    var durationSecs: Int
    var patternLabel: String?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = .now,
        sequence: [String],
        durationSecs: Int,
        patternLabel: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sequence = sequence
        self.durationSecs = durationSecs
        self.patternLabel = patternLabel
    }

    enum Columns: String, ColumnExpression {
        case id, timestamp, sequence, durationSecs, patternLabel
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, sequence, durationSecs, patternLabel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        durationSecs = try c.decode(Int.self, forKey: .durationSecs)
        patternLabel = try c.decodeIfPresent(String.self, forKey: .patternLabel)

        let seqStr = try c.decode(String.self, forKey: .sequence)
        if let data = seqStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            sequence = decoded
        } else {
            sequence = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(durationSecs, forKey: .durationSecs)
        try c.encodeIfPresent(patternLabel, forKey: .patternLabel)

        let seqData = try JSONEncoder().encode(sequence)
        try c.encode(String(data: seqData, encoding: .utf8) ?? "[]", forKey: .sequence)
    }
}
