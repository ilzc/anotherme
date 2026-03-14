import Foundation

/// Layer 1: Behavioral rhythm analysis. Builds daily rhythms from activity records
/// and uses AI to infer rhythm traits (chronotype, focus patterns, etc.).
enum Layer1Analyzer {

    /// Analyze a batch of activity records, producing DailyRhythm entries and updating RhythmTraits.
    static func analyze(
        records: [ActivityRecord],
        store: Layer1Store,
        aiClient: AIClient? = nil,
        onProgress: AnalysisProgressReport? = nil
    ) async throws {
        let calendar = Calendar.current

        // Group records by day
        let grouped = Dictionary(grouping: records) { record in
            calendar.startOfDay(for: record.timestamp)
        }

        await onProgress?("Grouped activity records into \(grouped.count) days")

        // Process each day
        for (dayStart, dayRecords) in grouped {
            let sorted = dayRecords.sorted { $0.timestamp < $1.timestamp }
            let rhythm = buildDailyRhythm(date: dayStart, records: sorted, calendar: calendar)

            // Check if rhythm already exists for this date; if so, update it
            if var existing = try store.fetchRhythm(for: dayStart) {
                existing.activeStart = rhythm.activeStart
                existing.activeEnd = rhythm.activeEnd
                existing.totalActiveMins = rhythm.totalActiveMins
                existing.appDistribution = rhythm.appDistribution
                existing.switchCount = rhythm.switchCount
                existing.focusScore = rhythm.focusScore
                existing.peakHours = rhythm.peakHours
                try store.insertRhythm(existing)
            } else {
                try store.insertRhythm(rhythm)
            }
        }

        await onProgress?("Daily rhythm data saved (\(grouped.count) days)")

        // Update rhythm traits if we have enough data (at least 7 days)
        let recentRhythms = try store.fetchRecentRhythms(limit: 30)
        if recentRhythms.count >= 7 {
            await onProgress?("Computing rhythm trait summary (\(recentRhythms.count) days of data)")
            let summary = buildRhythmSummary(rhythms: recentRhythms, records: records)

            await onProgress?("Saving local rhythm traits…")
            saveLocalTraits(summary: summary, store: store, rhythms: recentRhythms, records: records)

            // AI-based trait analysis (if available)
            if let aiClient {
                let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)
                if config.isConfigured {
                    await onProgress?("Calling AI to analyze rhythm traits…")
                    try await analyzeRhythmTraitsWithAI(
                        summary: summary, store: store, aiClient: aiClient,
                        config: config, evidenceCount: recentRhythms.count,
                        onProgress: onProgress
                    )
                } else {
                    await onProgress?("AI not configured, skipping deep analysis")
                }
            }
        } else {
            await onProgress?("Insufficient data (\(recentRhythms.count)/7 days), skipping trait analysis")
        }
    }

    // MARK: - Daily Rhythm Construction

    static func buildDailyRhythm(
        date: Date,
        records: [ActivityRecord],
        calendar: Calendar
    ) -> DailyRhythm {
        guard !records.isEmpty else {
            return DailyRhythm(id: UUID().uuidString, date: date)
        }

        let activeMins = calculateActiveMins(records: records, calendar: calendar)
        let switchCount = countAppSwitches(records: records)
        let focusScore = calculateFocusScore(records: records)
        let peakHours = findPeakHours(records: records, calendar: calendar)
        let appDist = buildAppDistribution(records: records)

        // Active start/end: earliest and latest timestamp formatted as HH:mm
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let activeStart = formatter.string(from: records.first!.timestamp)
        let activeEnd = formatter.string(from: records.last!.timestamp)

        return DailyRhythm(
            id: UUID().uuidString,
            date: date,
            activeStart: activeStart,
            activeEnd: activeEnd,
            totalActiveMins: activeMins,
            appDistribution: appDist,
            switchCount: switchCount,
            focusScore: focusScore,
            peakHours: peakHours
        )
    }

    /// Count distinct 5-minute time blocks, multiply by 5.
    static func calculateActiveMins(records: [ActivityRecord], calendar: Calendar) -> Int {
        var blocks = Set<Int>()
        for record in records {
            let hour = calendar.component(.hour, from: record.timestamp)
            let minute = calendar.component(.minute, from: record.timestamp)
            let blockIndex = hour * 12 + minute / 5  // 12 blocks per hour (each 5 min)
            blocks.insert(blockIndex)
        }
        return blocks.count * 5
    }

    /// Count adjacent records with different appName.
    static func countAppSwitches(records: [ActivityRecord]) -> Int {
        guard records.count > 1 else { return 0 }
        var switches = 0
        for i in 1..<records.count {
            if records[i].appName != records[i - 1].appName {
                switches += 1
            }
        }
        return switches
    }

    /// Focus score using three factors: engagement level, single-app streak, and switch frequency.
    static func calculateFocusScore(records: [ActivityRecord]) -> Double {
        guard !records.isEmpty else { return 0 }

        // Factor 1: Engagement level (if available)
        let engagementRecords = records.compactMap(\.engagementLevel)
        let engagementFactor: Double
        if !engagementRecords.isEmpty {
            var score = 0.0
            for level in engagementRecords {
                switch level {
                case "deep_focus": score += 1.0
                case "active_work": score += 0.7
                case "browsing": score += 0.3
                case "idle": score += 0.0
                default: score += 0.5
                }
            }
            engagementFactor = score / Double(engagementRecords.count)
        } else {
            engagementFactor = 0.5
        }

        // Factor 2: Longest single-app streak ratio
        var maxStreak = 1
        var currentStreak = 1
        for i in 1..<records.count {
            if records[i].appName == records[i - 1].appName {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 1
            }
        }
        let streakFactor = Double(maxStreak) / Double(records.count)

        // Factor 3: Low switch frequency (inverse)
        let switches = countAppSwitches(records: records)
        let activeHours = max(1.0, Double(records.count) * 5.0 / 60.0)
        let switchesPerHour = Double(switches) / activeHours
        let switchFactor = max(0, 1.0 - switchesPerHour / 20.0)

        // Weighted combination
        if !engagementRecords.isEmpty {
            return max(0, min(1.0, engagementFactor * 0.4 + streakFactor * 0.3 + switchFactor * 0.3))
        } else {
            return max(0, min(1.0, streakFactor * 0.5 + switchFactor * 0.5))
        }
    }

    /// Find top 4 hours by activity count.
    static func findPeakHours(records: [ActivityRecord], calendar: Calendar) -> [Int] {
        var hourCounts: [Int: Int] = [:]
        for record in records {
            let hour = calendar.component(.hour, from: record.timestamp)
            hourCounts[hour, default: 0] += 1
        }
        let sorted = hourCounts.sorted { $0.value > $1.value }
        return Array(sorted.prefix(4).map(\.key).sorted())
    }

    /// Build app distribution: count per appName times 5 (minutes per record).
    static func buildAppDistribution(records: [ActivityRecord]) -> [String: Int] {
        var dist: [String: Int] = [:]
        for record in records {
            dist[record.appName, default: 0] += 5
        }
        return dist
    }

    // MARK: - Rhythm Summary (Local Aggregation)

    struct RhythmSummary {
        let dayCount: Int
        let avgActiveHours: Double
        let avgStartTime: String
        let avgEndTime: String
        let avgFocusScore: Double
        let avgSwitchesPerHour: Double
        let topApps: [(name: String, mins: Int)]
        let workMins: Int
        let leisureMins: Int
        let otherMins: Int
        let commRatio: Double
        let commSessionCount: Int
        let avgCommSessionMins: Double
        let avgWeekdayMins: Double
        let avgWeekendMins: Double
        let avgWeekdayFocus: Double
        let avgWeekendFocus: Double
        let peakHours: [Int]
    }

    static func buildRhythmSummary(rhythms: [DailyRhythm], records: [ActivityRecord]) -> RhythmSummary {
        let calendar = Calendar.current

        // Focus & switches
        let avgFocus = rhythms.map(\.focusScore).reduce(0, +) / Double(rhythms.count)
        let avgSwitches = Double(rhythms.map(\.switchCount).reduce(0, +)) / Double(rhythms.count)
        let avgActiveMins = Double(rhythms.map(\.totalActiveMins).reduce(0, +)) / Double(rhythms.count)
        let avgSwitchesPerHour = avgActiveMins > 0 ? avgSwitches / (avgActiveMins / 60.0) : 0

        // Start/end times
        var totalStartMins = 0, startCount = 0, totalEndMins = 0, endCount = 0
        for rhythm in rhythms {
            if let s = rhythm.activeStart, let m = parseTimeToMinutes(s) { totalStartMins += m; startCount += 1 }
            if let e = rhythm.activeEnd, let m = parseTimeToMinutes(e) { totalEndMins += m; endCount += 1 }
        }
        let avgStartMin = startCount > 0 ? totalStartMins / startCount : 0
        let avgEndMin = endCount > 0 ? totalEndMins / endCount : 0

        // Top apps
        var totalAppMins: [String: Int] = [:]
        for rhythm in rhythms { for (app, mins) in rhythm.appDistribution { totalAppMins[app, default: 0] += mins } }
        let topApps = totalAppMins.sorted { $0.value > $1.value }.prefix(8).map { (name: $0.key, mins: $0.value) }

        // Work/leisure
        var workMins = 0, leisureMins = 0, otherMins = 0
        for record in records {
            switch record.activityCategory {
            case "work", "learning": workMins += 5
            case "entertainment", "social": leisureMins += 5
            default: otherMins += 5
            }
        }

        // Communication
        let commApps: Set<String> = ["slack", "teams", "discord", "telegram", "wechat", "微信",
                                      "mail", "outlook", "messages", "信息", "dingtalk", "飞书",
                                      "feishu", "lark", "zoom", "qq"]
        let commRecords = records.filter { r in
            commApps.contains(where: { r.appName.lowercased().contains($0) }) || r.activityCategory == "social"
        }
        let totalMins = records.count * 5
        let commMins = commRecords.count * 5
        let commRatio = totalMins > 0 ? Double(commMins) / Double(totalMins) : 0
        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        var commSessionCount = 0, inComm = false
        for rec in sorted {
            let isComm = commApps.contains(where: { rec.appName.lowercased().contains($0) }) || rec.activityCategory == "social"
            if isComm && !inComm { commSessionCount += 1; inComm = true } else if !isComm { inComm = false }
        }
        let avgCommMins = commSessionCount > 0 ? Double(commMins) / Double(commSessionCount) : 0

        // Weekday/weekend
        var weekdayMins: [Int] = [], weekendMins: [Int] = []
        var weekdayFocus: [Double] = [], weekendFocus: [Double] = []
        for rhythm in rhythms {
            let wd = calendar.component(.weekday, from: rhythm.date)
            if wd == 1 || wd == 7 {
                weekendMins.append(rhythm.totalActiveMins); weekendFocus.append(rhythm.focusScore)
            } else {
                weekdayMins.append(rhythm.totalActiveMins); weekdayFocus.append(rhythm.focusScore)
            }
        }

        // Peak hours across all rhythms
        var hourCounts: [Int: Int] = [:]
        for rhythm in rhythms { for h in rhythm.peakHours { hourCounts[h, default: 0] += 1 } }
        let peakHours = hourCounts.sorted { $0.value > $1.value }.prefix(4).map(\.key).sorted()

        return RhythmSummary(
            dayCount: rhythms.count,
            avgActiveHours: avgActiveMins / 60.0,
            avgStartTime: formatMinutesToTime(avgStartMin),
            avgEndTime: formatMinutesToTime(avgEndMin),
            avgFocusScore: avgFocus,
            avgSwitchesPerHour: avgSwitchesPerHour,
            topApps: Array(topApps),
            workMins: workMins,
            leisureMins: leisureMins,
            otherMins: otherMins,
            commRatio: commRatio,
            commSessionCount: commSessionCount,
            avgCommSessionMins: avgCommMins,
            avgWeekdayMins: weekdayMins.isEmpty ? 0 : Double(weekdayMins.reduce(0, +)) / Double(weekdayMins.count),
            avgWeekendMins: weekendMins.isEmpty ? 0 : Double(weekendMins.reduce(0, +)) / Double(weekendMins.count),
            avgWeekdayFocus: weekdayFocus.isEmpty ? 0 : weekdayFocus.reduce(0, +) / Double(weekdayFocus.count),
            avgWeekendFocus: weekendFocus.isEmpty ? 0 : weekendFocus.reduce(0, +) / Double(weekendFocus.count),
            peakHours: peakHours
        )
    }

    // MARK: - Local Traits (fast, no AI)

    /// Save basic factual data as traits (app_preferences, work_rhythm, etc.) — these don't need AI.
    private static func saveLocalTraits(summary: RhythmSummary, store: Layer1Store, rhythms: [DailyRhythm], records: [ActivityRecord]) {
        let evidenceCount = rhythms.count

        // App Preferences — factual data, no interpretation needed
        let topAppsArray = summary.topApps.map { ["name": $0.name, "mins": "\($0.mins)"] }
        let _ = try? upsertRhythmTrait(store: store, dimension: "app_preferences",
                                        value: jsonStringFromArray(topAppsArray), evidenceCount: evidenceCount)

        // Work/Leisure — factual distribution
        let _ = try? upsertRhythmTrait(store: store, dimension: "work_rhythm",
                                        value: jsonString(from: ["workMins": "\(summary.workMins)",
                                                                  "leisureMins": "\(summary.leisureMins)",
                                                                  "otherMins": "\(summary.otherMins)"]),
                                        evidenceCount: evidenceCount)
    }

    // MARK: - AI Trait Analysis

    private static func analyzeRhythmTraitsWithAI(
        summary: RhythmSummary,
        store: Layer1Store,
        aiClient: AIClient,
        config: AIModelSlot,
        evidenceCount: Int,
        onProgress: AnalysisProgressReport?
    ) async throws {
        let request = DeepAnalysisPrompt.buildLayer1Prompt(summary: summary)
        let response = try await aiClient.chatCompletion(config: config, request: request, debugFunction: "layer1_rhythm")
        let traits = try DeepAnalysisPrompt.parseTraitsResponse(response)

        await onProgress?("Saving AI analysis results (\(traits.count) trait dimensions)")

        for trait in traits {
            try upsertRhythmTrait(store: store, dimension: trait.dimension,
                                  value: trait.value, evidenceCount: evidenceCount)
        }
    }

    private static func upsertRhythmTrait(
        store: Layer1Store,
        dimension: String,
        value: String,
        evidenceCount: Int
    ) throws {
        let existing = try store.fetchTraits(dimension: dimension)
        if var trait = existing.first {
            trait.value = value
            trait.confidence = min(1.0, Double(evidenceCount) / 30.0)
            trait.evidenceCount = evidenceCount
            trait.lastUpdated = .now
            trait.version += 1
            try store.upsertTrait(trait)
        } else {
            let trait = RhythmTrait(
                id: UUID().uuidString,
                dimension: dimension,
                value: value,
                confidence: min(1.0, Double(evidenceCount) / 30.0),
                evidenceCount: evidenceCount,
                firstObserved: .now,
                lastUpdated: .now,
                version: 1
            )
            try store.upsertTrait(trait)
        }
    }

    // MARK: - Time Helpers

    private static func parseTimeToMinutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private static func formatMinutesToTime(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: - Helpers

    private static func jsonString(from dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private static func jsonStringFromArray(_ array: [[String: String]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }
}
