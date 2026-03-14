import Foundation

/// Generates a personality snapshot by collecting traits from all 5 layers and optionally
/// generating an AI summary.
enum SnapshotGenerator {

    /// All traits collected from 5 layers, used for serialization.
    struct AllTraitsDTO: Codable {
        let rhythmTraits: [TraitEntry]
        let knowledgeTraits: [TraitEntry]
        let cognitiveTraits: [TraitEntry]
        let expressionTraits: [TraitEntry]
        let valueTraits: [TraitEntry]

        struct TraitEntry: Codable {
            let dimension: String
            let value: String
            let confidence: Double
        }
    }

    /// Generate a personality snapshot from all layers.
    static func generate(
        trigger: ModelingScheduler.TriggerReason,
        stores: (Layer1Store, Layer2Store, Layer3Store, Layer4Store, Layer5Store),
        snapshotStore: SnapshotStore,
        aiClient: AIClient
    ) async throws {
        let (layer1Store, layer2Store, layer3Store, layer4Store, layer5Store) = stores

        // 1. Collect all traits from 5 layers
        let allTraits = try collectAllTraits(
            layer1Store: layer1Store,
            layer2Store: layer2Store,
            layer3Store: layer3Store,
            layer4Store: layer4Store,
            layer5Store: layer5Store
        )

        // 2. Serialize to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fullProfile = try encoder.encode(allTraits)
        let profileString = String(data: fullProfile, encoding: .utf8) ?? "{}"

        // 3. Generate AI summary (if configured; failure does not abort snapshot)
        var summaryText: String? = nil
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)
        if config.isConfigured {
            do {
                let request = DeepAnalysisPrompt.buildSnapshotSummaryPrompt(traitsJSON: profileString)
                let response = try await aiClient.chatCompletion(config: config, request: request, debugFunction: "snapshot_summary")
                summaryText = response.choices.first?.message.content
            } catch {
                print("[SnapshotGenerator] AI summary failed, saving snapshot without summary: \(error.localizedDescription)")
            }
        }

        // 4. Save snapshot
        let snapshot = PersonalitySnapshot(
            id: UUID().uuidString,
            snapshotDate: .now,
            fullProfile: profileString,
            summaryText: summaryText,
            trigger: trigger.rawValue
        )
        try snapshotStore.insert(snapshot)
    }

    // MARK: - Trait Collection

    private static func collectAllTraits(
        layer1Store: Layer1Store,
        layer2Store: Layer2Store,
        layer3Store: Layer3Store,
        layer4Store: Layer4Store,
        layer5Store: Layer5Store
    ) throws -> AllTraitsDTO {
        let rhythmTraits = try layer1Store.fetchTraits().map {
            AllTraitsDTO.TraitEntry(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
        }

        let knowledgeTraits = try layer2Store.fetchTraits().map {
            AllTraitsDTO.TraitEntry(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
        }

        let cognitiveTraits = try layer3Store.fetchTraits().map {
            AllTraitsDTO.TraitEntry(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
        }

        let expressionTraits = try layer4Store.fetchTraits().map {
            AllTraitsDTO.TraitEntry(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
        }

        let valueTraits = try layer5Store.fetchTraits().map {
            AllTraitsDTO.TraitEntry(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
        }

        return AllTraitsDTO(
            rhythmTraits: rhythmTraits,
            knowledgeTraits: knowledgeTraits,
            cognitiveTraits: cognitiveTraits,
            expressionTraits: expressionTraits,
            valueTraits: valueTraits
        )
    }
}
