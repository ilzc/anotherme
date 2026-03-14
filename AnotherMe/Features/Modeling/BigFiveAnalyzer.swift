import Foundation

/// Analyzes all 5 layers of personality traits to infer Big Five (OCEAN) scores.
enum BigFiveAnalyzer {

    /// Run Big Five analysis by collecting all layer traits and calling AI.
    static func analyze(
        stores: (Layer1Store, Layer2Store, Layer3Store, Layer4Store, Layer5Store),
        snapshotStore: SnapshotStore,
        aiClient: AIClient,
        onProgress: AnalysisProgressReport? = nil
    ) async throws -> BigFiveResult {
        let (l1Store, l2Store, l3Store, l4Store, l5Store) = stores

        // Step 1: Collect all trait values from 5 layers
        await onProgress?("Collecting personality trait data from 5 layers…")
        let allTraits = try SnapshotGenerator.AllTraitsDTO(
            rhythmTraits: l1Store.fetchTraits().map {
                .init(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
            },
            knowledgeTraits: l2Store.fetchTraits().map {
                .init(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
            },
            cognitiveTraits: l3Store.fetchTraits().map {
                .init(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
            },
            expressionTraits: l4Store.fetchTraits().map {
                .init(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
            },
            valueTraits: l5Store.fetchTraits().map {
                .init(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let traitsJSON = String(data: try encoder.encode(allTraits), encoding: .utf8) ?? "{}"

        // Step 2: Collect supplementary metrics
        await onProgress?("Collecting supplementary metrics…")
        let supplement = try collectSupplement(l1Store: l1Store, l2Store: l2Store)

        // Step 3: Build summary
        let summary = DeepAnalysisPrompt.BigFiveSummary(
            traitsJSON: traitsJSON,
            rhythmStability: supplement.rhythmStability,
            knowledgeDiversityIndex: supplement.knowledgeDiversityIndex,
            socialCategoryRatio: supplement.socialCategoryRatio,
            l2DomainDistribution: supplement.l2DomainDistribution,
            l2DepthDistribution: supplement.l2DepthDistribution,
            l2TopTopics: supplement.l2TopTopics
        )

        // Step 4: Call AI
        await onProgress?("Calling AI to infer Big Five personality…")
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)
        guard config.isConfigured else {
            throw AIClientError.notConfigured
        }

        let request = DeepAnalysisPrompt.buildBigFivePrompt(summary: summary)
        let response = try await aiClient.chatCompletion(
            config: config,
            request: request,
            debugFunction: "bigfive_analysis"
        )

        // Step 5: Parse and validate response
        await onProgress?("Parsing Big Five analysis results…")
        let bigfive = try DeepAnalysisPrompt.parseBigFiveResponse(response)

        // Validate all scores and confidence in [0, 1]
        let dimensions = [bigfive.openness, bigfive.conscientiousness, bigfive.extraversion,
                          bigfive.agreeableness, bigfive.neuroticism]
        guard dimensions.allSatisfy({ (0.0...1.0).contains($0.score) && (0.0...1.0).contains($0.confidence) }) else {
            throw AIClientError.invalidResponse
        }

        // Validate strength labels exist and are consistent with scores
        for dim in dimensions {
            let expectedStrength = Self.expectedStrength(for: dim.score)
            guard expectedStrength == dim.strength else {
                throw AIClientError.invalidResponse
            }
            // At least 2 evidence items per dimension
            guard dim.evidence.count >= 2 else {
                throw AIClientError.invalidResponse
            }
        }

        // Step 6: Build result model
        let avgConfidence = dimensions.map(\.confidence).reduce(0, +) / 5.0

        let result = BigFiveResult(
            opennessScore: bigfive.openness.score,
            opennessConfidence: bigfive.openness.confidence,
            opennessStrength: bigfive.openness.strength,
            opennessEvidence: encodeEvidence(bigfive.openness.evidence),
            conscientiousnessScore: bigfive.conscientiousness.score,
            conscientiousnessConfidence: bigfive.conscientiousness.confidence,
            conscientiousnessStrength: bigfive.conscientiousness.strength,
            conscientiousnessEvidence: encodeEvidence(bigfive.conscientiousness.evidence),
            extraversionScore: bigfive.extraversion.score,
            extraversionConfidence: bigfive.extraversion.confidence,
            extraversionStrength: bigfive.extraversion.strength,
            extraversionEvidence: encodeEvidence(bigfive.extraversion.evidence),
            agreeablenessScore: bigfive.agreeableness.score,
            agreeablenessConfidence: bigfive.agreeableness.confidence,
            agreeablenessStrength: bigfive.agreeableness.strength,
            agreeablenessEvidence: encodeEvidence(bigfive.agreeableness.evidence),
            neuroticismScore: bigfive.neuroticism.score,
            neuroticismConfidence: bigfive.neuroticism.confidence,
            neuroticismStrength: bigfive.neuroticism.strength,
            neuroticismEvidence: encodeEvidence(bigfive.neuroticism.evidence),
            summary: bigfive.summary,
            overallConfidence: avgConfidence
        )

        // Step 7: Persist
        await onProgress?("Saving Big Five results")
        try snapshotStore.insertBigFive(result)

        return result
    }

    // MARK: - Supplement Collection

    private struct Supplement {
        let rhythmStability: String
        let knowledgeDiversityIndex: String
        let socialCategoryRatio: String
        let l2DomainDistribution: String
        let l2DepthDistribution: String
        let l2TopTopics: String
    }

    private static func collectSupplement(l1Store: Layer1Store, l2Store: Layer2Store) throws -> Supplement {
        // Rhythm stability: standard deviation of focusScore
        let rhythms = try l1Store.fetchRecentRhythms(limit: 30)
        let rhythmStability: String
        if rhythms.count >= 3 {
            let scores = rhythms.map(\.focusScore)
            let mean = scores.reduce(0, +) / Double(scores.count)
            let variance = scores.map { pow($0 - mean, 2) }.reduce(0, +) / Double(scores.count)
            rhythmStability = String(format: "%.3f", sqrt(variance))
        } else {
            rhythmStability = "Insufficient data"
        }

        // Knowledge graph statistics (shared with MBTI)
        let allNodes = try l2Store.fetchAllNodes()

        // Diversity index
        let categories = Set(allNodes.map(\.category))
        let diversityIndex = allNodes.isEmpty ? "No data" :
            String(format: "%.2f (%d domains / %d topics)", Double(categories.count) / Double(allNodes.count), categories.count, allNodes.count)

        // Social category ratio
        let socialCount = allNodes.filter { $0.category.lowercased().contains("social") }.count
        let socialRatio = allNodes.isEmpty ? "No data" :
            String(format: "%.1f%% (%d / %d)", Double(socialCount) / Double(allNodes.count) * 100, socialCount, allNodes.count)

        // Domain distribution
        var categoryDist: [String: Int] = [:]
        for node in allNodes { categoryDist[node.category, default: 0] += 1 }
        let domainStr = categoryDist.sorted { $0.value > $1.value }
            .map { "\($0.key): \($0.value)" }.joined(separator: ", ")

        // Depth distribution
        let shallow = allNodes.filter { $0.depthScore < 0.2 }.count
        let moderate = allNodes.filter { $0.depthScore >= 0.2 && $0.depthScore < 0.5 }.count
        let deep = allNodes.filter { $0.depthScore >= 0.5 && $0.depthScore < 0.8 }.count
        let expert = allNodes.filter { $0.depthScore >= 0.8 }.count
        let depthStr = "shallow: \(shallow), moderate: \(moderate), deep: \(deep), expert: \(expert)"

        // Top topics by time
        let topByTime = allNodes.sorted { $0.totalTimeSpent > $1.totalTimeSpent }.prefix(15)
            .map { "\($0.topic)(\(String(format: "%.1f", Double($0.totalTimeSpent) / 3600.0))h, depth:\(String(format: "%.2f", $0.depthScore)))" }
            .joined(separator: ", ")

        return Supplement(
            rhythmStability: rhythmStability,
            knowledgeDiversityIndex: diversityIndex,
            socialCategoryRatio: socialRatio,
            l2DomainDistribution: domainStr.isEmpty ? "No data" : domainStr,
            l2DepthDistribution: depthStr,
            l2TopTopics: topByTime.isEmpty ? "No data" : topByTime
        )
    }

    // MARK: - Helpers

    /// Maps a 0-1 score to the expected strength label per prompt rules.
    /// Must match the AI prompt output format in DeepAnalysisPrompt.
    private static func expectedStrength(for score: Double) -> String {
        let distance = abs(score - 0.5)
        if distance >= 0.2 { return "strong" }     // score <=0.3 or >=0.7
        if distance > 0.05 { return "moderate" }   // score 0.3-0.45 or 0.55-0.7
        return "weak"                               // score 0.45-0.55
    }

    private static func encodeEvidence(_ evidence: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: evidence, options: []),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }
}
