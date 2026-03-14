import Foundation

/// Analyzes all 5 layers of personality traits to infer MBTI type.
enum MBTIAnalyzer {

    /// Run MBTI analysis by collecting all layer traits and calling AI.
    static func analyze(
        stores: (Layer1Store, Layer2Store, Layer3Store, Layer4Store, Layer5Store),
        snapshotStore: SnapshotStore,
        aiClient: AIClient,
        onProgress: AnalysisProgressReport? = nil
    ) async throws -> MBTIResult {
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

        // Step 2: Collect L2 ground-truth supplements
        await onProgress?("Collecting knowledge graph statistics…")
        let l2Supplement = try collectL2Supplement(store: l2Store)

        // Step 3: Build summary
        let summary = DeepAnalysisPrompt.MBTISummary(
            traitsJSON: traitsJSON,
            l2DomainDistribution: l2Supplement.domainDist,
            l2DepthDistribution: l2Supplement.depthDist,
            l2TopTopics: l2Supplement.topTopics
        )

        // Step 4: Call AI
        await onProgress?("Calling AI to infer MBTI type…")
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)
        guard config.isConfigured else {
            throw AIClientError.notConfigured
        }

        let request = DeepAnalysisPrompt.buildMBTIPrompt(summary: summary)
        let response = try await aiClient.chatCompletion(
            config: config,
            request: request,
            debugFunction: "mbti_analysis"
        )

        // Step 5: Parse and validate response
        await onProgress?("Parsing MBTI analysis results…")
        let mbti = try DeepAnalysisPrompt.parseMBTIResponse(response)

        // Validate MBTI type is exactly 4 valid letters
        let typeChars = Array(mbti.type.uppercased())
        guard typeChars.count == 4,
              ["E","I"].contains(String(typeChars[0])),
              ["S","N"].contains(String(typeChars[1])),
              ["T","F"].contains(String(typeChars[2])),
              ["J","P"].contains(String(typeChars[3])) else {
            throw AIClientError.invalidResponse
        }

        // Validate each dimension result matches its axis
        guard ["E","I"].contains(mbti.dimensions.EI.result),
              ["S","N"].contains(mbti.dimensions.SN.result),
              ["T","F"].contains(mbti.dimensions.TF.result),
              ["J","P"].contains(mbti.dimensions.JP.result) else {
            throw AIClientError.invalidResponse
        }

        // Step 6: Build result model
        let avgConfidence = (
            mbti.dimensions.EI.confidence +
            mbti.dimensions.SN.confidence +
            mbti.dimensions.TF.confidence +
            mbti.dimensions.JP.confidence
        ) / 4.0

        let result = MBTIResult(
            mbtiType: mbti.type,
            eiResult: mbti.dimensions.EI.result,
            eiConfidence: mbti.dimensions.EI.confidence,
            eiStrength: mbti.dimensions.EI.strength,
            eiEvidence: encodeEvidence(mbti.dimensions.EI.evidence),
            snResult: mbti.dimensions.SN.result,
            snConfidence: mbti.dimensions.SN.confidence,
            snStrength: mbti.dimensions.SN.strength,
            snEvidence: encodeEvidence(mbti.dimensions.SN.evidence),
            tfResult: mbti.dimensions.TF.result,
            tfConfidence: mbti.dimensions.TF.confidence,
            tfStrength: mbti.dimensions.TF.strength,
            tfEvidence: encodeEvidence(mbti.dimensions.TF.evidence),
            jpResult: mbti.dimensions.JP.result,
            jpConfidence: mbti.dimensions.JP.confidence,
            jpStrength: mbti.dimensions.JP.strength,
            jpEvidence: encodeEvidence(mbti.dimensions.JP.evidence),
            summary: mbti.summary,
            overallConfidence: avgConfidence
        )

        // Step 7: Persist
        await onProgress?("Saving MBTI result: \(result.mbtiType)")
        try snapshotStore.insertMBTI(result)

        return result
    }

    // MARK: - L2 Ground-truth

    private struct L2Supplement {
        let domainDist: String
        let depthDist: String
        let topTopics: String
    }

    private static func collectL2Supplement(store: Layer2Store) throws -> L2Supplement {
        let allNodes = try store.fetchAllNodes()

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

        return L2Supplement(
            domainDist: domainStr.isEmpty ? "No data" : domainStr,
            depthDist: depthStr,
            topTopics: topByTime.isEmpty ? "No data" : topByTime
        )
    }

    // MARK: - Helpers

    private static func encodeEvidence(_ evidence: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: evidence, options: []),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }
}
