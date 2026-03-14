import Foundation
import SwiftUI

/// Global application state, shared across the app.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    // MARK: - Services

    let permissionManager = PermissionManager()
    private(set) var captureService: CaptureService?
    private(set) var activityStore: ActivityStore?
    private(set) var analysisPipeline: AnalysisPipeline?

    // Layer stores
    private(set) var layer1Store: Layer1Store?
    private(set) var layer2Store: Layer2Store?
    private(set) var layer3Store: Layer3Store?
    private(set) var layer4Store: Layer4Store?
    private(set) var layer5Store: Layer5Store?
    private(set) var snapshotStore: SnapshotStore?
    private(set) var insightStore: InsightStore?
    private(set) var chatStore: ChatStore?
    private(set) var memoryStore: MemoryStore?
    private(set) var memoryConsolidator: MemoryConsolidator?

    // Phase 2: Modeling engine
    private(set) var modelingEngine: ModelingEngine?
    let modelingScheduler = ModelingScheduler()

    // MARK: - State

    var isSetupComplete = false
    private var activityToken: NSObjectProtocol?

    private init() {}

    // MARK: - Setup

    func setup() async throws {
        // 1. Initialize database
        try DatabaseManager.shared.setup()

        // 2. Create stores (activityDB is required, others are optional)
        let dbm = DatabaseManager.shared
        guard let activityPool = dbm.activityDB else {
            throw NSError(domain: "com.anotherme", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open activity database"])
        }
        activityStore = ActivityStore(db: activityPool)
        if let db = dbm.layer1DB { layer1Store = Layer1Store(db: db) }
        if let db = dbm.layer2DB { layer2Store = Layer2Store(db: db) }
        if let db = dbm.layer3DB { layer3Store = Layer3Store(db: db) }
        if let db = dbm.layer4DB { layer4Store = Layer4Store(db: db) }
        if let db = dbm.layer5DB { layer5Store = Layer5Store(db: db) }
        if let db = dbm.snapshotsDB { snapshotStore = SnapshotStore(db: db) }
        if let db = dbm.insightsDB { insightStore = InsightStore(db: db) }
        if let db = dbm.chatDB { chatStore = ChatStore(db: db) }
        if let db = dbm.memoryDB {
            memoryStore = MemoryStore(db: db)
            memoryConsolidator = MemoryConsolidator(memoryStore: memoryStore!)
        }

        // 3. Create analysis pipeline
        guard let activityStore else {
            throw NSError(domain: "com.anotherme", code: 2, userInfo: [NSLocalizedDescriptionKey: "Activity store not initialized"])
        }
        analysisPipeline = AnalysisPipeline(activityStore: activityStore)

        // 3b. Wire MemoryExtractor into pipeline if memory store is available
        if let memoryStore {
            let extractor = MemoryExtractor(memoryStore: memoryStore)
            await analysisPipeline?.setMemoryExtractor(extractor)
        }

        // 4. Create capture service
        guard let analysisPipeline else {
            throw NSError(domain: "com.anotherme", code: 3, userInfo: [NSLocalizedDescriptionKey: "Analysis pipeline not initialized"])
        }
        captureService = CaptureService(analysisPipeline: analysisPipeline)

        // 5. Disable App Nap for reliable timer scheduling
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "AnotherMe screen capture scheduling"
        )

        // 6. Check permissions
        await permissionManager.checkAll()

        // 7. Create modeling engine (Phase 2)
        if let l1 = layer1Store, let l2 = layer2Store, let l3 = layer3Store,
           let l4 = layer4Store, let l5 = layer5Store, let snap = snapshotStore {
            modelingEngine = ModelingEngine(
                activityStore: activityStore,
                layer1Store: l1, layer2Store: l2, layer3Store: l3,
                layer4Store: l4, layer5Store: l5,
                snapshotStore: snap,
                aiClient: .shared
            )
        }

        isSetupComplete = true
    }

    // MARK: - Modeling

    func startModeling() {
        guard let engine = modelingEngine else { return }
        let defaults = UserDefaults.standard
        let config = ModelingScheduler.Config(
            dailyAnalysisHour: defaults.integer(forKey: "modeling.dailyHour", default: 23),
            weeklyAnalysisDay: defaults.integer(forKey: "modeling.weeklyDay", default: 1),
            thresholdRecordCount: defaults.integer(forKey: "modeling.threshold", default: 200),
            enabled: defaults.bool(forKey: "modeling.enabled", default: true)
        )
        modelingScheduler.onTrigger = { [weak engine] trigger in
            guard let engine else { return }
            Task {
                await engine.runFullAnalysis(trigger: trigger)
            }
        }
        guard let activityStore else { return }
        modelingScheduler.start(config: config, activityStore: activityStore)
    }

    // MARK: - Capture Control

    func startCapture() {
        guard let captureService else { return }
        let config = CaptureService.Config(
            intervalSeconds: UserDefaults.standard.integer(forKey: SettingsKey.intervalSeconds, default: 300),
            eventDrivenEnabled: UserDefaults.standard.bool(forKey: SettingsKey.eventDrivenEnabled, default: true),
            smartSamplingEnabled: UserDefaults.standard.bool(forKey: SettingsKey.smartSamplingEnabled, default: true),
            showAnimation: UserDefaults.standard.bool(forKey: SettingsKey.captureAnimationEnabled, default: true)
        )
        captureService.start(config: config)
    }

    func stopCapture() {
        captureService?.stop()
    }

    // MARK: - Data Cleanup

    private var cleanupTask: Task<Void, Never>?

    func scheduleDailyCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? self?.activityStore?.pruneOldRecords()
                // Memory lifecycle
                try? self?.memoryStore?.decayUnaccessed()
                // Consolidate before hard prune: summarize low-value memories via AI
                try? await self?.memoryConsolidator?.consolidateIfNeeded()
                try? self?.memoryStore?.pruneByImportance()
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }
}

// MARK: - Settings Keys

enum SettingsKey {
    static let intervalEnabled = "capture.interval.enabled"
    static let intervalSeconds = "capture.interval.seconds"
    static let eventDrivenEnabled = "capture.event.enabled"
    static let smartSamplingEnabled = "capture.smart.enabled"
    static let captureAnimationEnabled = "capture.animation.enabled"
    static let selectedScreenIDs = "capture.selectedScreenIDs"
    static let launchAtLogin = "general.launchAtLogin"
    static let responseLanguage = "ai.response.language"
}

/// Returns the AI response language based on user setting or system locale.
/// Used to instruct AI prompts to output natural language content in this language.
func currentResponseLanguage() -> String {
    let stored = UserDefaults.standard.string(forKey: SettingsKey.responseLanguage)
    if let stored, !stored.isEmpty { return stored }
    // Auto-detect from system locale
    let lang = Locale.current.language.languageCode?.identifier ?? "en"
    switch lang {
    case "zh": return "Chinese"
    case "ja": return "Japanese"
    case "ko": return "Korean"
    case "fr": return "French"
    case "de": return "German"
    case "es": return "Spanish"
    default: return "English"
    }
}

/// Returns the language directive string to append to AI prompts.
/// Empty language returns an empty string (no directive).
func languageDirective(_ language: String) -> String {
    if language.isEmpty { return "" }
    return "\n\nIMPORTANT: You MUST respond in \(language)."
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) != nil ? bool(forKey: key) : defaultValue
    }

    func integer(forKey key: String, default defaultValue: Int) -> Int {
        object(forKey: key) != nil ? integer(forKey: key) : defaultValue
    }
}
