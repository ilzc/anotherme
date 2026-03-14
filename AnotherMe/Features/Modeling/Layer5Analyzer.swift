import Foundation

/// Layer 5: Values & priorities analysis. Uses cross-layer data to infer deep values via AI.
enum Layer5Analyzer {

    /// Minimum number of records required before running values analysis.
    private static let minRecordCount = 100

    /// Analyze activity records to infer value traits using cross-layer data.
    static func analyze(
        records: [ActivityRecord],
        store: Layer5Store,
        aiClient: AIClient,
        layer1Store: Layer1Store,
        layer2Store: Layer2Store,
        onProgress: AnalysisProgressReport? = nil
    ) async throws {
        await onProgress?("Checking data volume: \(records.count) records (need ≥\(minRecordCount))")
        guard records.count >= minRecordCount else {
            await onProgress?("Insufficient data (\(records.count)/\(minRecordCount)), skipping values analysis")
            return
        }

        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)
        guard config.isConfigured else {
            await onProgress?("AI not configured, skipping deep analysis")
            return
        }

        // 1. Build enriched value summary from cross-layer data
        await onProgress?("Collecting cross-layer data (Layer1 rhythms + Layer2 knowledge nodes)")
        let categoryDist = buildCategoryDistribution(records)
        let topics = try extractPersistentTopics(layer2Store)
        let wlRatio = try calculateWorkLifeRatio(layer1Store)

        // Content summaries (sampled)
        let contentSummaries = records
            .compactMap(\.contentSummary)
            .filter { !$0.isEmpty }
            .suffix(30)
            .map { String($0.prefix(200)) }

        // User intents (sampled)
        let userIntents = records
            .compactMap(\.userIntent)
            .filter { !$0.isEmpty }
            .suffix(20)
            .map { String($0.prefix(150)) }

        // Engagement breakdown
        var engagementBreakdown: [String: Int] = [:]
        for record in records {
            if let level = record.engagementLevel {
                engagementBreakdown[level, default: 0] += 1
            }
        }

        // Category time estimates (each record ~5 min)
        let categoryTimeEstimates = categoryDist.mapValues { $0 * 5 }

        // Learning record count
        let learningCount = records.filter { $0.activityCategory == "learning" }.count

        // App switch patterns
        let switchPatterns = buildSwitchPatterns(records)

        await onProgress?("Building values analysis summary...")
        let summary = ValueSummary(
            categoryDistribution: categoryDist,
            persistentTopics: topics,
            workLifeRatio: wlRatio,
            totalRecords: records.count,
            contentSummaries: Array(contentSummaries),
            userIntents: Array(userIntents),
            engagementBreakdown: engagementBreakdown,
            categoryTimeEstimates: categoryTimeEstimates,
            learningRecordCount: learningCount,
            topAppSwitchPatterns: switchPatterns
        )

        // 2. AI analysis
        await onProgress?("Calling AI to infer values...")
        let request = DeepAnalysisPrompt.buildLayer5Prompt(summary: summary)
        let response = try await aiClient.chatCompletion(config: config, request: request, debugFunction: "layer5_values")
        let traits = try DeepAnalysisPrompt.parseTraitsResponse(response)

        // 3. Upsert value traits
        await onProgress?("Saving value traits (\(traits.count) dimensions)")
        for parsed in traits {
            try upsertValueTrait(store: store, parsed: parsed, evidenceCount: records.count)
        }
    }

    // MARK: - Category Distribution

    static func buildCategoryDistribution(_ records: [ActivityRecord]) -> [String: Int] {
        var distribution: [String: Int] = [:]
        for record in records {
            distribution[record.activityCategory, default: 0] += 1
        }
        return distribution
    }

    // MARK: - Persistent Topics

    static func extractPersistentTopics(_ layer2Store: Layer2Store) throws -> [String] {
        let topNodes = try layer2Store.fetchTopNodes(limit: 10)
        return topNodes.map(\.topic)
    }

    // MARK: - Work/Life Ratio

    static func calculateWorkLifeRatio(_ layer1Store: Layer1Store) throws -> Double {
        let rhythms = try layer1Store.fetchRecentRhythms(limit: 30)
        guard !rhythms.isEmpty else { return 0.5 }

        let calendar = Calendar.current
        var weekdayMins = 0
        var weekendMins = 0
        var weekdayCount = 0
        var weekendCount = 0

        for rhythm in rhythms {
            let weekday = calendar.component(.weekday, from: rhythm.date)
            if weekday == 1 || weekday == 7 {
                weekendMins += rhythm.totalActiveMins
                weekendCount += 1
            } else {
                weekdayMins += rhythm.totalActiveMins
                weekdayCount += 1
            }
        }

        let avgWeekday = weekdayCount > 0 ? Double(weekdayMins) / Double(weekdayCount) : 0
        let avgWeekend = weekendCount > 0 ? Double(weekendMins) / Double(weekendCount) : 0
        let total = avgWeekday + avgWeekend

        guard total > 0 else { return 0.5 }
        return avgWeekday / total
    }

    // MARK: - App Switch Patterns

    /// Build top switch patterns like ["Xcode->Slack:15", "Slack->Xcode:12"]
    static func buildSwitchPatterns(_ records: [ActivityRecord]) -> [String] {
        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        var patterns: [String: Int] = [:]
        for i in 1..<sorted.count {
            let prev = sorted[i - 1].appName
            let curr = sorted[i].appName
            if prev != curr {
                patterns["\(prev)->\(curr)", default: 0] += 1
            }
        }
        return patterns.sorted { $0.value > $1.value }
            .prefix(10)
            .map { "\($0.key):\($0.value)" }
    }

    // MARK: - Trait Upsert (Incremental)

    private static func upsertValueTrait(
        store: Layer5Store,
        parsed: ParsedTrait,
        evidenceCount: Int
    ) throws {
        let existing = try store.fetchTraits(dimension: parsed.dimension)
        if var trait = existing.first {
            trait.value = parsed.value
            trait.description = parsed.description ?? trait.description
            trait.confidence = (trait.confidence * 0.3 + parsed.confidence * 0.7)
            trait.evidenceCount += evidenceCount
            trait.lastUpdated = .now
            trait.version += 1
            try store.upsertTrait(trait)
        } else {
            try store.upsertTrait(ValueTrait(
                dimension: parsed.dimension,
                value: parsed.value,
                description: parsed.description,
                confidence: parsed.confidence,
                evidenceCount: evidenceCount
            ))
        }
    }
}
