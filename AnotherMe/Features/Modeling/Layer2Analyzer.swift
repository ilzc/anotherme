import Foundation

/// Layer 2: Pure local knowledge graph building. Analyzes activity records into knowledge nodes, edges, and traits.
enum Layer2Analyzer {

    /// Analyze a batch of activity records, building/updating the knowledge graph.
    static func analyze(
        records: [ActivityRecord],
        store: Layer2Store,
        aiClient: AIClient? = nil,
        onProgress: AnalysisProgressReport? = nil
    ) async throws {
        // --- Phase 1: Aggregate topic stats from records ---
        var topicStats: [String: TopicAggregation] = [:]

        for record in records {
            for topic in record.topics {
                var agg = topicStats[topic] ?? TopicAggregation()
                agg.count += 1
                agg.totalSecs += effectiveSeconds(for: record)
                if agg.firstSeen == nil || record.timestamp < agg.firstSeen! {
                    agg.firstSeen = record.timestamp
                }
                if agg.lastSeen == nil || record.timestamp > agg.lastSeen! {
                    agg.lastSeen = record.timestamp
                }
                agg.categoryCounts[record.activityCategory, default: 0] += 1
                let dayKey = dayString(from: record.timestamp)
                agg.distinctDays.insert(dayKey)
                topicStats[topic] = agg
            }
        }

        await onProgress?("Aggregating topic stats (\(topicStats.count) topics)")

        // --- Phase 2: Upsert KnowledgeNode for each topic ---
        var topicNodeIds: [String: String] = [:]

        for (topic, agg) in topicStats {
            let dominantCategory = agg.categoryCounts.max(by: { $0.value < $1.value })?.key ?? "other"

            if var existing = try store.fetchNode(byTopic: topic) {
                existing.totalTimeSpent += agg.totalSecs
                existing.visitCount += agg.count
                if dominantCategory != "other" {
                    existing.category = dominantCategory
                }
                if let first = agg.firstSeen, first < existing.firstSeen {
                    existing.firstSeen = first
                }
                if let last = agg.lastSeen, last > existing.lastSeen {
                    existing.lastSeen = last
                }
                existing.depthScore = calculateDepthScore(
                    totalTimeSecs: existing.totalTimeSpent,
                    visitCount: existing.visitCount,
                    revisitDays: agg.distinctDays.count,
                    lastSeen: existing.lastSeen
                )
                try store.upsertNode(existing)
                topicNodeIds[topic] = existing.id
            } else {
                let node = KnowledgeNode(
                    id: UUID().uuidString,
                    topic: topic,
                    category: dominantCategory,
                    totalTimeSpent: agg.totalSecs,
                    visitCount: agg.count,
                    depthScore: calculateDepthScore(
                        totalTimeSecs: agg.totalSecs,
                        visitCount: agg.count,
                        revisitDays: agg.distinctDays.count
                    ),
                    firstSeen: agg.firstSeen ?? .now,
                    lastSeen: agg.lastSeen ?? .now
                )
                try store.upsertNode(node)
                topicNodeIds[topic] = node.id
            }
        }

        await onProgress?("Updated \(topicNodeIds.count) knowledge nodes")

        // --- Phase 3: Build co-occurrence edges (30-minute window across records) ---
        await onProgress?("Building co-occurrence relationships (\(records.count) records)")
        let coOccurrences = buildCoOccurrences(records: records, topicNodeIds: topicNodeIds)

        for (key, count) in coOccurrences {
            let parts = key.split(separator: "|")
            guard parts.count == 2 else { continue }
            let sourceId = String(parts[0])
            let targetId = String(parts[1])

            if var existing = try store.fetchEdge(source: sourceId, target: targetId) {
                existing.coOccurrenceCount += count
                existing.strength = calculateEdgeStrength(coOccurrenceCount: existing.coOccurrenceCount)
                try store.upsertEdge(existing)
            } else {
                let edge = KnowledgeEdge(
                    id: UUID().uuidString,
                    sourceNodeId: sourceId,
                    targetNodeId: targetId,
                    coOccurrenceCount: count,
                    strength: calculateEdgeStrength(coOccurrenceCount: count)
                )
                try store.upsertEdge(edge)
            }
        }

        await onProgress?("Updated \(coOccurrences.count) knowledge edges")

        // --- Phase 4: Update knowledge traits ---
        try await updateKnowledgeTraits(records: records, store: store, aiClient: aiClient, onProgress: onProgress)
    }

    // MARK: - Co-occurrence (30-minute window)

    private static func buildCoOccurrences(
        records: [ActivityRecord],
        topicNodeIds: [String: String]
    ) -> [String: Int] {
        var coOccurrences: [String: Int] = [:]
        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        let windowSecs: Double = 30 * 60

        for i in 0..<sorted.count {
            let topicsI = sorted[i].topics

            // Intra-record pairing
            if topicsI.count >= 2 {
                for a in 0..<topicsI.count {
                    for b in (a + 1)..<topicsI.count {
                        guard let idA = topicNodeIds[topicsI[a]],
                              let idB = topicNodeIds[topicsI[b]] else { continue }
                        let key = idA < idB ? "\(idA)|\(idB)" : "\(idB)|\(idA)"
                        coOccurrences[key, default: 0] += 1
                    }
                }
            }

            // Cross-record pairing within 30-minute window
            for j in (i + 1)..<sorted.count {
                let timeDiff = sorted[j].timestamp.timeIntervalSince(sorted[i].timestamp)
                if timeDiff > windowSecs { break }

                let topicsJ = sorted[j].topics
                for tA in topicsI {
                    for tB in topicsJ where tA != tB {
                        guard let idA = topicNodeIds[tA],
                              let idB = topicNodeIds[tB] else { continue }
                        let key = idA < idB ? "\(idA)|\(idB)" : "\(idB)|\(idA)"
                        coOccurrences[key, default: 0] += 1
                    }
                }
            }
        }
        return coOccurrences
    }

    // MARK: - Engagement Weighting

    private static func effectiveSeconds(for record: ActivityRecord) -> Int {
        switch record.engagementLevel {
        case "deep_focus", "active_work": return 300
        case "browsing": return 150
        case "idle": return 0
        default: return 200
        }
    }

    // MARK: - Depth Score

    /// Calculate depth score using weighted factors:
    /// timeFactor(0.4) + revisitFactor(0.3) + avgTimeFactor(0.3), then apply recency decay.
    /// revisitDays = number of distinct days the topic was seen (more meaningful than raw visit count)
    static func calculateDepthScore(totalTimeSecs: Int, visitCount: Int, revisitDays: Int = 1, lastSeen: Date? = nil) -> Double {
        // timeFactor: normalize total time (cap at 100 hours = 360000 secs)
        let timeFactor = min(1.0, Double(totalTimeSecs) / 360_000.0)

        // revisitFactor: distinct days visited (cap at 30 days)
        let revisitFactor = min(1.0, Double(max(revisitDays, 1)) / 30.0)

        // avgTimeFactor: average time per visit (cap at 30 min = 1800 secs)
        let avgTime = visitCount > 0 ? Double(totalTimeSecs) / Double(visitCount) : 0
        let avgTimeFactor = min(1.0, avgTime / 1800.0)

        var score = timeFactor * 0.4 + revisitFactor * 0.3 + avgTimeFactor * 0.3

        // Recency decay: topics not seen in 30+ days start losing depth score
        if let lastSeen {
            let daysSince = max(0, -lastSeen.timeIntervalSinceNow / 86400.0)
            if daysSince > 30 {
                let recencyFactor = min(1.0, 30.0 / daysSince)
                score *= recencyFactor
            }
        }

        return score
    }

    // MARK: - Edge Strength

    static func calculateEdgeStrength(coOccurrenceCount: Int) -> Double {
        min(1.0, log(Double(coOccurrenceCount) + 1) / log(101.0))
    }

    // MARK: - Knowledge Traits

    private static func updateKnowledgeTraits(records: [ActivityRecord], store: Layer2Store, aiClient: AIClient?, onProgress: AnalysisProgressReport?) async throws {
        let allNodes = try store.fetchAllNodes()
        guard !allNodes.isEmpty else { return }

        // Build summary for AI
        let recentNodes = allNodes.filter { $0.firstSeen > Date().addingTimeInterval(-7 * 86400) }
        let categorySet = Set(allNodes.map(\.category))
        let diversityIndex = Double(categorySet.count) / 8.0

        var deepTopics: [String] = []
        var expertTopics: [String] = []
        for node in allNodes {
            if node.depthScore >= 0.8 { expertTopics.append(node.topic) }
            else if node.depthScore >= 0.5 { deepTopics.append(node.topic) }
        }

        var categoryDist: [String: Int] = [:]
        for node in allNodes { categoryDist[node.category, default: 0] += 1 }
        let domainStr = categoryDist.sorted { $0.value > $1.value }
            .map { "\($0.key): \($0.value)" }.joined(separator: ", ")

        // Learning style stats
        let learningRecords = records.filter { $0.activityCategory == "learning" }
        var systematic = 0, practiceCount = 0, community = 0
        for record in learningRecords {
            let app = record.appName.lowercased()
            if app.contains("safari") || app.contains("chrome") || app.contains("firefox")
                || app.contains("arc") || app.contains("preview") || app.contains("books") {
                systematic += 1
            } else if app.contains("xcode") || app.contains("vscode") || app.contains("terminal")
                || app.contains("iterm") || app.contains("cursor") {
                practiceCount += 1
            } else if app.contains("slack") || app.contains("discord") || app.contains("reddit") {
                community += 1
            }
        }
        let learningStr = learningRecords.isEmpty ? "No learning records" :
            "Reading:\(systematic), Practice:\(practiceCount), Community:\(community)"

        // Top topics by time
        let topByTime = allNodes.sorted { $0.totalTimeSpent > $1.totalTimeSpent }.prefix(15)
            .map { "\($0.topic)(\(String(format: "%.1f", Double($0.totalTimeSpent) / 3600.0))h, depth:\(String(format: "%.2f", $0.depthScore)))" }
            .joined(separator: ", ")

        // Top edges
        let edges = try store.fetchStrongestEdges(limit: 10)
        let nodeMap = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0.topic) })
        let edgesStr: String = edges.map {
            let s = nodeMap[$0.sourceNodeId] ?? "?"
            let t = nodeMap[$0.targetNodeId] ?? "?"
            return "\(s)<->\(t)(\($0.coOccurrenceCount)x)"
        }.joined(separator: ", ")

        let summary = Layer2TraitSummary(
            totalTopics: allNodes.count,
            newTopicsLast7Days: recentNodes.count,
            diversityIndex: diversityIndex,
            deepTopics: deepTopics,
            expertTopics: expertTopics,
            domainDistribution: domainStr,
            learningStyleStats: learningStr,
            topTopicsByTime: topByTime,
            topEdges: edgesStr
        )

        // AI analysis
        guard let aiClient else {
            await onProgress?("No AI client, skipping deep analysis")
            return
        }
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)
        guard config.isConfigured else {
            await onProgress?("AI not configured, skipping deep analysis")
            return
        }

        await onProgress?("Calling AI to analyze knowledge traits…")
        let request = DeepAnalysisPrompt.buildLayer2Prompt(summary: summary)
        let response = try await aiClient.chatCompletion(config: config, request: request, debugFunction: "layer2_knowledge")
        let traits = try DeepAnalysisPrompt.parseTraitsResponse(response)

        await onProgress?("Saving knowledge traits (\(traits.count) dimensions)")
        for trait in traits {
            try upsertKnowledgeTrait(store: store, dimension: trait.dimension, value: trait.value)
        }
    }

    private static func upsertKnowledgeTrait(
        store: Layer2Store,
        dimension: String,
        value: String
    ) throws {
        let existing = try store.fetchTraits(dimension: dimension)
        if var trait = existing.first {
            trait.value = value
            trait.lastUpdated = .now
            trait.version += 1
            try store.upsertTrait(trait)
        } else {
            let trait = KnowledgeTrait(
                id: UUID().uuidString,
                dimension: dimension,
                value: value,
                confidence: 0.5,
                lastUpdated: .now,
                version: 1
            )
            try store.upsertTrait(trait)
        }
    }

    // MARK: - Helpers

    private static func jsonString(from dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

// MARK: - Internal Aggregation

private struct TopicAggregation {
    var count: Int = 0
    var totalSecs: Int = 0
    var firstSeen: Date?
    var lastSeen: Date?
    var categoryCounts: [String: Int] = [:]
    var distinctDays: Set<String> = []
}
