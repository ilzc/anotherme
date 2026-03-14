import Foundation
import GRDB

/// A reusable trait record shared by layers 1 (rhythm_traits), 2 (knowledge_traits),
/// 3 (cognitive_traits), 4 (expression_traits), and 5 (value_traits).
/// Each layer uses a different table name but identical schema.
struct PersonalityTrait: Codable, FetchableRecord, PersistableRecord, Identifiable {

    /// Set per-layer to the correct table name.
    /// Default is empty; callers must use the typed aliases below.
    static let databaseTableName = ""

    var id: String
    var dimension: String
    var value: String              // JSON
    var confidence: Double
    var evidenceCount: Int
    var firstObserved: Date
    var lastUpdated: Date
    var version: Int

    init(
        id: String = UUID().uuidString,
        dimension: String,
        value: String,
        confidence: Double = 0,
        evidenceCount: Int = 0,
        firstObserved: Date = .now,
        lastUpdated: Date = .now,
        version: Int = 1
    ) {
        self.id = id
        self.dimension = dimension
        self.value = value
        self.confidence = confidence
        self.evidenceCount = evidenceCount
        self.firstObserved = firstObserved
        self.lastUpdated = lastUpdated
        self.version = version
    }

    enum Columns: String, ColumnExpression {
        case id, dimension, value, confidence
        case evidenceCount, firstObserved, lastUpdated, version
    }
}

// MARK: - Layer-Specific Type Aliases with Table Names

/// Layer 1: Behavioral rhythm traits
struct RhythmTrait: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "rhythm_traits"

    var id: String
    var dimension: String
    var value: String
    var confidence: Double
    var evidenceCount: Int
    var firstObserved: Date
    var lastUpdated: Date
    var version: Int

    init(from trait: PersonalityTrait) {
        self.id = trait.id
        self.dimension = trait.dimension
        self.value = trait.value
        self.confidence = trait.confidence
        self.evidenceCount = trait.evidenceCount
        self.firstObserved = trait.firstObserved
        self.lastUpdated = trait.lastUpdated
        self.version = trait.version
    }

    init(
        id: String = UUID().uuidString,
        dimension: String,
        value: String,
        confidence: Double = 0,
        evidenceCount: Int = 0,
        firstObserved: Date = .now,
        lastUpdated: Date = .now,
        version: Int = 1
    ) {
        self.id = id
        self.dimension = dimension
        self.value = value
        self.confidence = confidence
        self.evidenceCount = evidenceCount
        self.firstObserved = firstObserved
        self.lastUpdated = lastUpdated
        self.version = version
    }

    enum Columns: String, ColumnExpression {
        case id, dimension, value, confidence
        case evidenceCount, firstObserved, lastUpdated, version
    }
}

/// Layer 2: Knowledge traits
struct KnowledgeTrait: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "knowledge_traits"

    var id: String
    var dimension: String
    var value: String
    var confidence: Double
    var lastUpdated: Date
    var version: Int

    init(
        id: String = UUID().uuidString,
        dimension: String,
        value: String,
        confidence: Double = 0,
        lastUpdated: Date = .now,
        version: Int = 1
    ) {
        self.id = id
        self.dimension = dimension
        self.value = value
        self.confidence = confidence
        self.lastUpdated = lastUpdated
        self.version = version
    }

    enum Columns: String, ColumnExpression {
        case id, dimension, value, confidence, lastUpdated, version
    }
}

/// Layer 3: Cognitive style traits
struct CognitiveTrait: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "cognitive_traits"

    var id: String
    var dimension: String
    var value: String
    var description: String?
    var confidence: Double
    var evidenceCount: Int
    var firstObserved: Date
    var lastUpdated: Date
    var version: Int

    init(
        id: String = UUID().uuidString,
        dimension: String,
        value: String,
        description: String? = nil,
        confidence: Double = 0,
        evidenceCount: Int = 0,
        firstObserved: Date = .now,
        lastUpdated: Date = .now,
        version: Int = 1
    ) {
        self.id = id
        self.dimension = dimension
        self.value = value
        self.description = description
        self.confidence = confidence
        self.evidenceCount = evidenceCount
        self.firstObserved = firstObserved
        self.lastUpdated = lastUpdated
        self.version = version
    }

    enum Columns: String, ColumnExpression {
        case id, dimension, value, description, confidence
        case evidenceCount, firstObserved, lastUpdated, version
    }
}

/// Layer 4: Communication / expression traits
struct ExpressionTrait: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "expression_traits"

    var id: String
    var dimension: String
    var value: String
    var confidence: Double
    var lastUpdated: Date
    var version: Int

    init(
        id: String = UUID().uuidString,
        dimension: String,
        value: String,
        confidence: Double = 0,
        lastUpdated: Date = .now,
        version: Int = 1
    ) {
        self.id = id
        self.dimension = dimension
        self.value = value
        self.confidence = confidence
        self.lastUpdated = lastUpdated
        self.version = version
    }

    enum Columns: String, ColumnExpression {
        case id, dimension, value, confidence, lastUpdated, version
    }
}

/// Layer 5: Values & priorities traits
struct ValueTrait: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "value_traits"

    var id: String
    var dimension: String
    var value: String
    var description: String?
    var confidence: Double
    var evidenceCount: Int
    var firstObserved: Date
    var lastUpdated: Date
    var version: Int

    init(
        id: String = UUID().uuidString,
        dimension: String,
        value: String,
        description: String? = nil,
        confidence: Double = 0,
        evidenceCount: Int = 0,
        firstObserved: Date = .now,
        lastUpdated: Date = .now,
        version: Int = 1
    ) {
        self.id = id
        self.dimension = dimension
        self.value = value
        self.description = description
        self.confidence = confidence
        self.evidenceCount = evidenceCount
        self.firstObserved = firstObserved
        self.lastUpdated = lastUpdated
        self.version = version
    }

    enum Columns: String, ColumnExpression {
        case id, dimension, value, description, confidence
        case evidenceCount, firstObserved, lastUpdated, version
    }
}
