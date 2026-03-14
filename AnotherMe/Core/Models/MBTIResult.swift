import Foundation
import GRDB

/// Stores a single MBTI analysis result.
struct MBTIResult: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "mbti_results"

    var id: String
    var analysisDate: Date
    var mbtiType: String              // e.g. "INTJ"
    var eiResult: String              // "E" or "I"
    var eiConfidence: Double
    var eiStrength: String            // strong/moderate/weak
    var eiEvidence: String            // JSON array of strings
    var snResult: String              // "S" or "N"
    var snConfidence: Double
    var snStrength: String
    var snEvidence: String
    var tfResult: String              // "T" or "F"
    var tfConfidence: Double
    var tfStrength: String
    var tfEvidence: String
    var jpResult: String              // "J" or "P"
    var jpConfidence: Double
    var jpStrength: String
    var jpEvidence: String
    var summary: String               // AI-generated overall description
    var overallConfidence: Double      // average of 4 dimensions

    init(
        id: String = UUID().uuidString,
        analysisDate: Date = .now,
        mbtiType: String,
        eiResult: String, eiConfidence: Double, eiStrength: String, eiEvidence: String,
        snResult: String, snConfidence: Double, snStrength: String, snEvidence: String,
        tfResult: String, tfConfidence: Double, tfStrength: String, tfEvidence: String,
        jpResult: String, jpConfidence: Double, jpStrength: String, jpEvidence: String,
        summary: String,
        overallConfidence: Double
    ) {
        self.id = id
        self.analysisDate = analysisDate
        self.mbtiType = mbtiType
        self.eiResult = eiResult; self.eiConfidence = eiConfidence; self.eiStrength = eiStrength; self.eiEvidence = eiEvidence
        self.snResult = snResult; self.snConfidence = snConfidence; self.snStrength = snStrength; self.snEvidence = snEvidence
        self.tfResult = tfResult; self.tfConfidence = tfConfidence; self.tfStrength = tfStrength; self.tfEvidence = tfEvidence
        self.jpResult = jpResult; self.jpConfidence = jpConfidence; self.jpStrength = jpStrength; self.jpEvidence = jpEvidence
        self.summary = summary
        self.overallConfidence = overallConfidence
    }

    enum Columns: String, ColumnExpression {
        case id, analysisDate, mbtiType
        case eiResult, eiConfidence, eiStrength, eiEvidence
        case snResult, snConfidence, snStrength, snEvidence
        case tfResult, tfConfidence, tfStrength, tfEvidence
        case jpResult, jpConfidence, jpStrength, jpEvidence
        case summary, overallConfidence
    }
}
