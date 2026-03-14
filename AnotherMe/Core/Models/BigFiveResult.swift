import Foundation
import GRDB

/// Stores a single Big Five (OCEAN) personality analysis result.
struct BigFiveResult: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "bigfive_results"

    var id: String
    var analysisDate: Date

    // O - Openness to Experience
    var opennessScore: Double           // 0.0-1.0
    var opennessConfidence: Double      // 0.0-1.0
    var opennessStrength: String        // strong/moderate/weak
    var opennessEvidence: String        // JSON array of strings

    // C - Conscientiousness
    var conscientiousnessScore: Double
    var conscientiousnessConfidence: Double
    var conscientiousnessStrength: String
    var conscientiousnessEvidence: String

    // E - Extraversion
    var extraversionScore: Double
    var extraversionConfidence: Double
    var extraversionStrength: String
    var extraversionEvidence: String

    // A - Agreeableness
    var agreeablenessScore: Double
    var agreeablenessConfidence: Double
    var agreeablenessStrength: String
    var agreeablenessEvidence: String

    // N - Neuroticism
    var neuroticismScore: Double
    var neuroticismConfidence: Double
    var neuroticismStrength: String
    var neuroticismEvidence: String

    // Summary
    var summary: String
    var overallConfidence: Double        // 5-dimension average

    init(
        id: String = UUID().uuidString,
        analysisDate: Date = .now,
        opennessScore: Double, opennessConfidence: Double, opennessStrength: String, opennessEvidence: String,
        conscientiousnessScore: Double, conscientiousnessConfidence: Double, conscientiousnessStrength: String, conscientiousnessEvidence: String,
        extraversionScore: Double, extraversionConfidence: Double, extraversionStrength: String, extraversionEvidence: String,
        agreeablenessScore: Double, agreeablenessConfidence: Double, agreeablenessStrength: String, agreeablenessEvidence: String,
        neuroticismScore: Double, neuroticismConfidence: Double, neuroticismStrength: String, neuroticismEvidence: String,
        summary: String,
        overallConfidence: Double
    ) {
        self.id = id
        self.analysisDate = analysisDate
        self.opennessScore = opennessScore; self.opennessConfidence = opennessConfidence
        self.opennessStrength = opennessStrength; self.opennessEvidence = opennessEvidence
        self.conscientiousnessScore = conscientiousnessScore; self.conscientiousnessConfidence = conscientiousnessConfidence
        self.conscientiousnessStrength = conscientiousnessStrength; self.conscientiousnessEvidence = conscientiousnessEvidence
        self.extraversionScore = extraversionScore; self.extraversionConfidence = extraversionConfidence
        self.extraversionStrength = extraversionStrength; self.extraversionEvidence = extraversionEvidence
        self.agreeablenessScore = agreeablenessScore; self.agreeablenessConfidence = agreeablenessConfidence
        self.agreeablenessStrength = agreeablenessStrength; self.agreeablenessEvidence = agreeablenessEvidence
        self.neuroticismScore = neuroticismScore; self.neuroticismConfidence = neuroticismConfidence
        self.neuroticismStrength = neuroticismStrength; self.neuroticismEvidence = neuroticismEvidence
        self.summary = summary
        self.overallConfidence = overallConfidence
    }

    enum Columns: String, ColumnExpression {
        case id, analysisDate
        case opennessScore, opennessConfidence, opennessStrength, opennessEvidence
        case conscientiousnessScore, conscientiousnessConfidence, conscientiousnessStrength, conscientiousnessEvidence
        case extraversionScore, extraversionConfidence, extraversionStrength, extraversionEvidence
        case agreeablenessScore, agreeablenessConfidence, agreeablenessStrength, agreeablenessEvidence
        case neuroticismScore, neuroticismConfidence, neuroticismStrength, neuroticismEvidence
        case summary, overallConfidence
    }
}
