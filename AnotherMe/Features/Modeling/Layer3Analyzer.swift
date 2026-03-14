import Foundation

/// Layer 3: Cognitive style analysis. Combines local behavior extraction with AI deep analysis.
enum Layer3Analyzer {

    /// Each record is assumed to represent ~5 minutes of activity.
    private static let minutesPerRecord = 5

    /// Analyze activity records to extract cognitive style traits and problem-solving sequences.
    static func analyze(
        records: [ActivityRecord],
        store: Layer3Store,
        aiClient: AIClient,
        onProgress: AnalysisProgressReport? = nil
    ) async throws {
        guard !records.isEmpty else { return }

        // 1. Extract and save problem-solving sequences
        await onProgress?("Extracting problem-solving sequences...")
        let sequences = extractProblemSolvingSequences(records)
        for seq in sequences {
            try store.insertSequence(seq)
        }
        await onProgress?("Found \(sequences.count) problem-solving sequences")

        // 2. Extract behavior summary from records
        await onProgress?("Building behavior summary (\(records.count) records)")
        let summary = extractBehaviorSummary(records)

        // 3. Call AI deep analysis (skip if not configured)
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)
        guard config.isConfigured else {
            await onProgress?("AI not configured, skipping deep analysis")
            return
        }

        await onProgress?("Calling AI for cognitive style analysis...")
        let request = DeepAnalysisPrompt.buildLayer3Prompt(summary: summary)
        let response = try await aiClient.chatCompletion(config: config, request: request, debugFunction: "layer3_cognitive")
        let traits = try DeepAnalysisPrompt.parseTraitsResponse(response)

        // 4. Upsert traits with incremental update
        await onProgress?("Saving cognitive features (\(traits.count) dimensions)")
        for parsed in traits {
            try upsertCognitiveTrait(store: store, parsed: parsed, evidenceCount: records.count)
        }
    }

    // MARK: - Behavior Summary Extraction

    static func extractBehaviorSummary(_ records: [ActivityRecord]) -> BehaviorSummary {
        let sorted = records.sorted { $0.timestamp < $1.timestamp }

        let avgSwitchesPerHour = calculateAvgSwitchesPerHour(sorted)
        let avgSessionMinutes = calculateAvgSessionMinutes(sorted)
        let searchReadPracticeRatio = calculateSearchReadPracticeRatio(sorted)
        let multiWindowFrequency = calculateMultiWindowFrequency(sorted)

        // Engagement distribution
        var engagementDist: [String: Int] = [:]
        for record in records {
            if let level = record.engagementLevel {
                engagementDist[level, default: 0] += 1
            }
        }

        // Average visible apps count
        let visibleCounts = records.compactMap { $0.visibleApps?.count }
        let avgVisibleApps = visibleCounts.isEmpty ? 0.0 : Double(visibleCounts.reduce(0, +)) / Double(visibleCounts.count)

        // Top intents
        let intentCounts = Dictionary(grouping: records.compactMap(\.userIntent).filter { !$0.isEmpty }) { $0 }
            .mapValues(\.count)
        let topIntents = intentCounts.sorted { $0.value > $1.value }.prefix(5).map(\.key)

        // Top apps
        var appCounts: [String: Int] = [:]
        for record in records {
            appCounts[record.appName, default: 0] += 1
        }
        let topApps = appCounts.sorted { $0.value > $1.value }.prefix(8).map { (app: $0.key, count: $0.value) }

        // Dominant topics
        var topicCounts: [String: Int] = [:]
        for record in records {
            for topic in record.topics {
                topicCounts[topic, default: 0] += 1
            }
        }
        let dominantTopics = topicCounts.sorted { $0.value > $1.value }.prefix(10).map(\.key)

        // Sample activities (contentSummary)
        let sampleActivities = records
            .compactMap(\.contentSummary)
            .filter { !$0.isEmpty }
            .suffix(10)
            .map { String($0.prefix(200)) }

        // Problem-solving pattern counts
        let sequences = extractProblemSolvingSequences(records)
        var patternCounts: [String: Int] = [:]
        for seq in sequences {
            if let label = seq.patternLabel {
                patternCounts[label, default: 0] += 1
            }
        }

        return BehaviorSummary(
            avgSwitchesPerHour: avgSwitchesPerHour,
            avgSessionMinutes: avgSessionMinutes,
            searchReadPracticeRatio: searchReadPracticeRatio,
            multiWindowFrequency: multiWindowFrequency,
            totalRecords: records.count,
            engagementDistribution: engagementDist,
            avgVisibleAppsCount: avgVisibleApps,
            topIntents: Array(topIntents),
            topApps: Array(topApps),
            dominantTopics: Array(dominantTopics),
            sampleActivities: Array(sampleActivities),
            problemSolvingPatterns: patternCounts
        )
    }

    /// Count app switches and divide by total hours of activity span.
    private static func calculateAvgSwitchesPerHour(_ sorted: [ActivityRecord]) -> Double {
        guard sorted.count > 1 else { return 0 }

        var switches = 0
        for i in 1..<sorted.count {
            if sorted[i].appName != sorted[i - 1].appName {
                switches += 1
            }
        }

        let totalHours = max(
            sorted.last!.timestamp.timeIntervalSince(sorted.first!.timestamp) / 3600.0,
            1.0
        )
        return Double(switches) / totalHours
    }

    /// Group consecutive same-app records into sessions; average their durations.
    private static func calculateAvgSessionMinutes(_ sorted: [ActivityRecord]) -> Double {
        guard !sorted.isEmpty else { return 0 }

        var sessions: [Double] = []
        var sessionStart = 0

        for i in 1..<sorted.count {
            if sorted[i].appName != sorted[i - 1].appName {
                let count = i - sessionStart
                sessions.append(Double(count * minutesPerRecord))
                sessionStart = i
            }
        }
        // Last session
        let lastCount = sorted.count - sessionStart
        sessions.append(Double(lastCount * minutesPerRecord))

        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0, +) / Double(sessions.count)
    }

    /// Classify records using categorizeStep and compute a ratio string like "30:50:20".
    private static func calculateSearchReadPracticeRatio(_ records: [ActivityRecord]) -> String {
        var search = 0
        var read = 0
        var practice = 0

        for record in records {
            let step = categorizeStep(record)
            switch step {
            case "search":
                search += 1
            case "read":
                read += 1
            case "code", "write", "design", "test":
                practice += 1
            default:
                break
            }
        }

        let total = search + read + practice
        guard total > 0 else { return "0:0:0" }

        let s = Int(round(Double(search) / Double(total) * 100))
        let r = Int(round(Double(read) / Double(total) * 100))
        let p = max(0, 100 - s - r)
        return "\(s):\(r):\(p)"
    }

    /// Calculate multi-window frequency using visibleApps when available,
    /// falling back to timestamp-based heuristic.
    private static func calculateMultiWindowFrequency(_ sorted: [ActivityRecord]) -> Double {
        // Primary: use visibleApps if available
        let visibleAppsCounts = sorted.compactMap { $0.visibleApps?.count }
        if !visibleAppsCounts.isEmpty {
            let multiCount = visibleAppsCounts.filter { $0 >= 2 }.count
            return Double(multiCount) / Double(visibleAppsCounts.count)
        }

        // Fallback: timestamp-based heuristic
        guard sorted.count > 1 else { return 0 }

        var multiWindowCount = 0
        var totalPairs = 0

        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
            if gap < 60 && gap >= 0 {
                totalPairs += 1
                if sorted[i].appName != sorted[i - 1].appName {
                    multiWindowCount += 1
                }
            }
        }

        guard totalPairs > 0 else { return 0 }
        return Double(multiWindowCount) / Double(totalPairs)
    }

    // MARK: - Problem Solving Sequences

    /// Extract problem-solving sequences from records.
    /// Groups consecutive records within 10-min gaps into sequences.
    /// Only saves sequences with 3+ steps.
    static func extractProblemSolvingSequences(_ records: [ActivityRecord]) -> [ProblemSolvingSequence] {
        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return [] }

        var sequences: [ProblemSolvingSequence] = []
        var currentGroup: [ActivityRecord] = [sorted[0]]

        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
            if gap <= 600 { // 10 minutes
                currentGroup.append(sorted[i])
            } else {
                if let seq = buildSequence(from: currentGroup) {
                    sequences.append(seq)
                }
                currentGroup = [sorted[i]]
            }
        }
        // Process last group
        if let seq = buildSequence(from: currentGroup) {
            sequences.append(seq)
        }

        return sequences
    }

    private static func buildSequence(from group: [ActivityRecord]) -> ProblemSolvingSequence? {
        guard group.count >= 3 else { return nil }

        let steps = group.map { categorizeStep($0) }
        let durationSecs = Int(group.last!.timestamp.timeIntervalSince(group.first!.timestamp))
        let label = inferPatternLabel(steps)

        return ProblemSolvingSequence(
            id: UUID().uuidString,
            timestamp: group.first!.timestamp,
            sequence: steps,
            durationSecs: max(durationSecs, 0),
            patternLabel: label
        )
    }

    /// Map an activity record to a step type using appName, userIntent, and activityCategory.
    private static func categorizeStep(_ record: ActivityRecord) -> String {
        let app = record.appName.lowercased()
        let intent = (record.userIntent ?? "").lowercased()
        let category = record.activityCategory.lowercased()

        // Browsers
        let browserApps: Set<String> = ["safari", "google chrome", "chrome", "firefox", "arc", "edge", "brave", "opera"]
        let isInBrowser = browserApps.contains(where: { app.contains($0) })

        // Search: browser with search-related intent
        if isInBrowser && (intent.contains("search") || intent.contains("搜索") || intent.contains("查找")
            || intent.contains("google") || intent.contains("stackoverflow")) {
            return "search"
        }

        // Read: browser reading articles/docs, or learning category in browser
        if isInBrowser && (category == "learning"
            || intent.contains("read") || intent.contains("阅读") || intent.contains("文档")
            || intent.contains("参考") || intent.contains("doc")) {
            return "read"
        }

        // Browser with no specific intent: classify as "read" (browsing = reading content)
        if isInBrowser {
            return "read"
        }

        // Read: dedicated reading apps
        let readApps: Set<String> = ["preview", "books", "kindle", "pdf", "reader"]
        if readApps.contains(where: { app.contains($0) }) {
            return "read"
        }

        // Code vs Test/Debug: IDEs and terminals
        let codeApps: Set<String> = ["xcode", "visual studio code", "vscode", "cursor", "intellij",
                                      "android studio", "sublime", "nova", "bbedit", "pycharm", "webstorm"]
        let terminalApps: Set<String> = ["terminal", "iterm", "warp", "alacritty", "kitty"]
        let isCodeOrTerminal = codeApps.contains(where: { app.contains($0) })
            || terminalApps.contains(where: { app.contains($0) })

        if isCodeOrTerminal {
            if intent.contains("debug") || intent.contains("test") || intent.contains("调试") || intent.contains("测试") {
                return "test"
            }
            return "code"
        }

        // Write/Document: writing and note apps
        let writeApps: Set<String> = ["pages", "word", "notion", "obsidian", "bear", "notes",
                                       "typora", "ulysses", "drafts", "scrivener", "备忘录", "textedit"]
        if writeApps.contains(where: { app.contains($0) }) {
            return "write"
        }

        // Design: creative/design tools
        let designApps: Set<String> = ["figma", "sketch", "photoshop", "illustrator", "canva", "affinity"]
        if designApps.contains(where: { app.contains($0) }) || category == "creative" {
            return "design"
        }

        // Communicate: messaging, email, video calls
        let commApps: Set<String> = ["slack", "teams", "discord", "telegram", "wechat", "微信",
                                      "mail", "outlook", "zoom", "messages", "信息", "dingtalk", "飞书", "feishu", "lark"]
        if commApps.contains(where: { app.contains($0) }) || category == "social" {
            return "communicate"
        }

        // Fallback from activityCategory
        switch category {
        case "learning": return "read"
        case "work": return "code"
        default: return "other"
        }
    }

    /// Infer a pattern label from the sequence of steps.
    private static func inferPatternLabel(_ steps: [String]) -> String? {
        let uniqueSteps = Set(steps)
        if uniqueSteps.count == 1 {
            return "focused_\(steps[0])"
        }
        if steps.contains("search") && steps.contains("read") && steps.contains("code") {
            return "research_then_implement"
        }
        if steps.contains("code") && steps.contains("test") {
            return "code_test_cycle"
        }
        if steps.contains("search") && steps.contains("read") {
            return "information_gathering"
        }
        if steps.contains("design") && steps.contains("code") {
            return "design_implement"
        }
        if steps.contains("communicate") && steps.contains("code") {
            return "communicate_then_implement"
        }
        if uniqueSteps.count >= 4 {
            return "exploratory"
        }
        return nil
    }

    // MARK: - Trait Upsert (Incremental)

    private static func upsertCognitiveTrait(
        store: Layer3Store,
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
            try store.upsertTrait(CognitiveTrait(
                dimension: parsed.dimension,
                value: parsed.value,
                description: parsed.description,
                confidence: parsed.confidence,
                evidenceCount: evidenceCount
            ))
        }
    }
}
