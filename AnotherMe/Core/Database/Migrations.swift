import Foundation
import GRDB

/// Manages database schema migrations across all SQLite files.
struct AppDatabaseMigrator {

    // MARK: - Activity Database

    static func migrateActivityDB(_ db: DatabasePool) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_create_activity_logs") { db in
            try db.create(table: "activity_logs", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("appName", .text).notNull()
                t.column("windowTitle", .text).notNull().defaults(to: "")
                t.column("extractedText", .text)
                t.column("contentSummary", .text)
                t.column("activityCategory", .text).notNull().defaults(to: "other")
                t.column("topics", .text).notNull().defaults(to: "[]")
                t.column("screenIndex", .integer).notNull().defaults(to: 0)
                t.column("captureMode", .text).notNull()
                t.column("analyzed", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v2_add_analysis_fields") { db in
            try db.alter(table: "activity_logs") { t in
                t.add(column: "userIntent", .text)
                t.add(column: "visibleApps", .text)
                t.add(column: "userAuthored", .text)
                t.add(column: "engagementLevel", .text)
            }
        }

        migrator.registerMigration("v3_add_activity_indexes") { db in
            try db.create(
                index: "idx_activity_logs_appName",
                on: "activity_logs",
                columns: ["appName"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_activity_logs_activityCategory",
                on: "activity_logs",
                columns: ["activityCategory"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_activity_logs_analyzed",
                on: "activity_logs",
                columns: ["analyzed"],
                ifNotExists: true
            )
        }

        migrator.registerMigration("v4_add_user_expressions") { db in
            try db.alter(table: "activity_logs") { t in
                t.add(column: "userExpressions", .text)
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Layer 1: Behavioral Rhythms

    static func migrateLayer1DB(_ db: DatabasePool) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_create_daily_rhythms") { db in
            try db.create(table: "daily_rhythms", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("date", .date).notNull().unique()
                t.column("activeStart", .text)       // HH:mm
                t.column("activeEnd", .text)         // HH:mm
                t.column("totalActiveMins", .integer).notNull().defaults(to: 0)
                t.column("appDistribution", .text).notNull().defaults(to: "{}") // JSON
                t.column("switchCount", .integer).notNull().defaults(to: 0)
                t.column("focusScore", .double).notNull().defaults(to: 0)
                t.column("peakHours", .text).notNull().defaults(to: "[]")       // JSON [Int]
            }
        }

        migrator.registerMigration("v1_create_rhythm_traits") { db in
            try db.create(table: "rhythm_traits", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("dimension", .text).notNull().indexed()
                t.column("value", .text).notNull()           // JSON
                t.column("confidence", .double).notNull().defaults(to: 0)
                t.column("evidenceCount", .integer).notNull().defaults(to: 0)
                t.column("firstObserved", .datetime).notNull()
                t.column("lastUpdated", .datetime).notNull()
                t.column("version", .integer).notNull().defaults(to: 1)
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Layer 2: Knowledge Graph

    static func migrateLayer2DB(_ db: DatabasePool) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_create_knowledge_nodes") { db in
            try db.create(table: "knowledge_nodes", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("topic", .text).notNull().indexed()
                t.column("category", .text).notNull().defaults(to: "other")
                t.column("totalTimeSpent", .integer).notNull().defaults(to: 0) // seconds
                t.column("visitCount", .integer).notNull().defaults(to: 0)
                t.column("depthScore", .double).notNull().defaults(to: 0)
                t.column("firstSeen", .datetime).notNull()
                t.column("lastSeen", .datetime).notNull()
            }
        }

        migrator.registerMigration("v1_create_knowledge_edges") { db in
            try db.create(table: "knowledge_edges", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("sourceNodeId", .text).notNull().references("knowledge_nodes", onDelete: .cascade)
                t.column("targetNodeId", .text).notNull().references("knowledge_nodes", onDelete: .cascade)
                t.column("coOccurrenceCount", .integer).notNull().defaults(to: 0)
                t.column("strength", .double).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v1_create_knowledge_traits") { db in
            try db.create(table: "knowledge_traits", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("dimension", .text).notNull().indexed()
                t.column("value", .text).notNull()
                t.column("confidence", .double).notNull().defaults(to: 0)
                t.column("lastUpdated", .datetime).notNull()
                t.column("version", .integer).notNull().defaults(to: 1)
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Layer 3: Cognitive Style

    static func migrateLayer3DB(_ db: DatabasePool) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_create_cognitive_traits") { db in
            try db.create(table: "cognitive_traits", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("dimension", .text).notNull().indexed()
                t.column("value", .text).notNull()
                t.column("confidence", .double).notNull().defaults(to: 0)
                t.column("evidenceCount", .integer).notNull().defaults(to: 0)
                t.column("firstObserved", .datetime).notNull()
                t.column("lastUpdated", .datetime).notNull()
                t.column("version", .integer).notNull().defaults(to: 1)
            }
        }

        migrator.registerMigration("v2_add_cognitive_description") { db in
            try db.alter(table: "cognitive_traits") { t in
                t.add(column: "description", .text)
            }
        }

        migrator.registerMigration("v1_create_problem_solving_sequences") { db in
            try db.create(table: "problem_solving_sequences", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("sequence", .text).notNull()  // JSON array
                t.column("durationSecs", .integer).notNull()
                t.column("patternLabel", .text)
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Layer 4: Communication Persona

    static func migrateLayer4DB(_ db: DatabasePool) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_create_expression_traits") { db in
            try db.create(table: "expression_traits", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("dimension", .text).notNull().indexed()
                t.column("value", .text).notNull()
                t.column("confidence", .double).notNull().defaults(to: 0)
                t.column("lastUpdated", .datetime).notNull()
                t.column("version", .integer).notNull().defaults(to: 1)
            }
        }

        migrator.registerMigration("v1_create_writing_samples") { db in
            try db.create(table: "writing_samples", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("context", .text).notNull()    // work_chat, email, etc.
                t.column("content", .text).notNull()
                t.column("sentiment", .text)
                t.column("wordCount", .integer).notNull().defaults(to: 0)
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Layer 5: Values & Priorities

    static func migrateLayer5DB(_ db: DatabasePool) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_create_value_traits") { db in
            try db.create(table: "value_traits", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("dimension", .text).notNull().indexed()
                t.column("value", .text).notNull()
                t.column("confidence", .double).notNull().defaults(to: 0)
                t.column("evidenceCount", .integer).notNull().defaults(to: 0)
                t.column("firstObserved", .datetime).notNull()
                t.column("lastUpdated", .datetime).notNull()
                t.column("version", .integer).notNull().defaults(to: 1)
            }
        }

        migrator.registerMigration("v2_add_value_description") { db in
            try db.alter(table: "value_traits") { t in
                t.add(column: "description", .text)
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Snapshots

    static func migrateSnapshotsDB(_ db: DatabasePool) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_create_personality_snapshots") { db in
            try db.create(table: "personality_snapshots", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("snapshotDate", .datetime).notNull().indexed()
                t.column("fullProfile", .text).notNull()   // JSON
                t.column("summaryText", .text)
                t.column("trigger", .text).notNull()       // daily/weekly/threshold
            }
        }

        migrator.registerMigration("v2_create_mbti_results") { db in
            try db.create(table: "mbti_results", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("analysisDate", .datetime).notNull().indexed()
                t.column("mbtiType", .text).notNull()
                t.column("eiResult", .text).notNull()
                t.column("eiConfidence", .double).notNull()
                t.column("eiStrength", .text).notNull()
                t.column("eiEvidence", .text).notNull()
                t.column("snResult", .text).notNull()
                t.column("snConfidence", .double).notNull()
                t.column("snStrength", .text).notNull()
                t.column("snEvidence", .text).notNull()
                t.column("tfResult", .text).notNull()
                t.column("tfConfidence", .double).notNull()
                t.column("tfStrength", .text).notNull()
                t.column("tfEvidence", .text).notNull()
                t.column("jpResult", .text).notNull()
                t.column("jpConfidence", .double).notNull()
                t.column("jpStrength", .text).notNull()
                t.column("jpEvidence", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("overallConfidence", .double).notNull()
            }
        }

        migrator.registerMigration("v3_create_bigfive_results") { db in
            try db.create(table: "bigfive_results", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("analysisDate", .datetime).notNull().indexed()
                t.column("opennessScore", .double).notNull()
                t.column("opennessConfidence", .double).notNull()
                t.column("opennessStrength", .text).notNull()
                t.column("opennessEvidence", .text).notNull()
                t.column("conscientiousnessScore", .double).notNull()
                t.column("conscientiousnessConfidence", .double).notNull()
                t.column("conscientiousnessStrength", .text).notNull()
                t.column("conscientiousnessEvidence", .text).notNull()
                t.column("extraversionScore", .double).notNull()
                t.column("extraversionConfidence", .double).notNull()
                t.column("extraversionStrength", .text).notNull()
                t.column("extraversionEvidence", .text).notNull()
                t.column("agreeablenessScore", .double).notNull()
                t.column("agreeablenessConfidence", .double).notNull()
                t.column("agreeablenessStrength", .text).notNull()
                t.column("agreeablenessEvidence", .text).notNull()
                t.column("neuroticismScore", .double).notNull()
                t.column("neuroticismConfidence", .double).notNull()
                t.column("neuroticismStrength", .text).notNull()
                t.column("neuroticismEvidence", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("overallConfidence", .double).notNull()
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Insights

    static func migrateInsightsDB(_ db: DatabasePool) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_create_insights") { db in
            try db.create(table: "insights", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("type", .text).notNull()          // anomaly/pattern/milestone/daily/weekly
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("relatedLayers", .text).notNull().defaults(to: "[]") // JSON [Int]
                t.column("notified", .boolean).notNull().defaults(to: false)
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Chat

    static func migrateChatDB(_ db: DatabasePool) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_create_chat_sessions") { db in
            try db.create(table: "chat_sessions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("createdAt", .datetime).notNull()
                t.column("title", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v1_create_chat_messages") { db in
            try db.create(table: "chat_messages", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("sessionId", .text).notNull().indexed()
                    .references("chat_sessions", onDelete: .cascade)
                t.column("timestamp", .datetime).notNull()
                t.column("role", .text).notNull()           // user/agent
                t.column("content", .text).notNull()
                t.column("referencedLayers", .text).notNull().defaults(to: "[]")
                t.column("referencedData", .text).notNull().defaults(to: "{}")
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Memory

    static func migrateMemoryDB(_ db: DatabasePool) throws {
        var migrator = GRDB.DatabaseMigrator()

        migrator.registerMigration("v1_create_memories") { db in
            try db.create(table: "memories", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("content", .text).notNull()
                t.column("category", .text).notNull().indexed()
                t.column("keywords", .text).notNull().defaults(to: "[]")
                t.column("embedding", .blob)
                t.column("importance", .double).notNull().defaults(to: 0.5)
                t.column("accessCount", .integer).notNull().defaults(to: 0)
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("sourceType", .text).notNull()
                t.column("sourceId", .text)
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("lastAccessedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v2_add_isConsolidated") { db in
            try db.alter(table: "memories") { t in
                t.add(column: "isConsolidated", .boolean).notNull().defaults(to: false)
            }
        }

        try migrator.migrate(db)
    }
}
