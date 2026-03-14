import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "com.anotherme", category: "DatabaseManager")

final class DatabaseManager {
    static let shared = DatabaseManager()

    private let dbDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        dbDirectory = appSupport.appendingPathComponent("AnotherMe", isDirectory: true)
    }

    // MARK: - Database Pools

    private(set) var activityDB: DatabasePool?
    private(set) var layer1DB: DatabasePool?
    private(set) var layer2DB: DatabasePool?
    private(set) var layer3DB: DatabasePool?
    private(set) var layer4DB: DatabasePool?
    private(set) var layer5DB: DatabasePool?
    private(set) var snapshotsDB: DatabasePool?
    private(set) var insightsDB: DatabasePool?
    private(set) var chatDB: DatabasePool?
    private(set) var memoryDB: DatabasePool?

    // MARK: - Lifecycle

    func setup() throws {
        try ensureDirectoryExists()

        // Open all database pools, logging failures instead of crashing
        do { activityDB = try openDatabase(name: "activity.sqlite") }
        catch { logger.error("Failed to open activity database: \(error.localizedDescription)") }

        do { layer1DB = try openDatabase(name: "layer1_rhythms.sqlite") }
        catch { logger.error("Failed to open layer1 database: \(error.localizedDescription)") }

        do { layer2DB = try openDatabase(name: "layer2_knowledge.sqlite") }
        catch { logger.error("Failed to open layer2 database: \(error.localizedDescription)") }

        do { layer3DB = try openDatabase(name: "layer3_cognitive.sqlite") }
        catch { logger.error("Failed to open layer3 database: \(error.localizedDescription)") }

        do { layer4DB = try openDatabase(name: "layer4_expression.sqlite") }
        catch { logger.error("Failed to open layer4 database: \(error.localizedDescription)") }

        do { layer5DB = try openDatabase(name: "layer5_values.sqlite") }
        catch { logger.error("Failed to open layer5 database: \(error.localizedDescription)") }

        do { snapshotsDB = try openDatabase(name: "snapshots.sqlite") }
        catch { logger.error("Failed to open snapshots database: \(error.localizedDescription)") }

        do { insightsDB = try openDatabase(name: "insights.sqlite") }
        catch { logger.error("Failed to open insights database: \(error.localizedDescription)") }

        do { chatDB = try openDatabase(name: "chat.sqlite") }
        catch { logger.error("Failed to open chat database: \(error.localizedDescription)") }

        do { memoryDB = try openDatabase(name: "memory.sqlite") }
        catch { logger.error("Failed to open memory database: \(error.localizedDescription)") }

        // Migrate all successfully opened databases
        if let db = activityDB { try AppDatabaseMigrator.migrateActivityDB(db) }
        if let db = layer1DB { try AppDatabaseMigrator.migrateLayer1DB(db) }
        if let db = layer2DB { try AppDatabaseMigrator.migrateLayer2DB(db) }
        if let db = layer3DB { try AppDatabaseMigrator.migrateLayer3DB(db) }
        if let db = layer4DB { try AppDatabaseMigrator.migrateLayer4DB(db) }
        if let db = layer5DB { try AppDatabaseMigrator.migrateLayer5DB(db) }
        if let db = snapshotsDB { try AppDatabaseMigrator.migrateSnapshotsDB(db) }
        if let db = insightsDB { try AppDatabaseMigrator.migrateInsightsDB(db) }
        if let db = chatDB { try AppDatabaseMigrator.migrateChatDB(db) }
        if let db = memoryDB { try AppDatabaseMigrator.migrateMemoryDB(db) }
    }

    func resetAll() throws {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: dbDirectory,
            includingPropertiesForKeys: nil
        )
        for file in files where file.pathExtension == "sqlite" {
            try fileManager.removeItem(at: file)
            // Also clean up WAL and SHM journal files
            let basePath = file.path
            try? fileManager.removeItem(atPath: basePath + "-wal")
            try? fileManager.removeItem(atPath: basePath + "-shm")
        }
        try KeychainManager.shared.deleteDatabaseKey()
    }

    // MARK: - Private

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: dbDirectory,
            withIntermediateDirectories: true
        )
    }

    func openDatabase(name: String) throws -> DatabasePool {
        try ensureDirectoryExists()

        let path = dbDirectory.appendingPathComponent(name).path

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        return try DatabasePool(path: path, configuration: config)
    }
}
