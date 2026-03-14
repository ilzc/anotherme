import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case minimal = "Plain Text"
    case card = "Personality Card"
    case structuredJSON = "Structured JSON"
    case fullArchive = "Full Archive"

    var id: String { rawValue }
}

enum ExportError: Error, LocalizedError {
    case noData
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noData: return "No personality data to export"
        case .encodingFailed: return "Data encoding failed"
        }
    }
}

/// Exports personality data in 4 formats.
struct PersonalityExporter {
    let layer1Store: Layer1Store
    let layer2Store: Layer2Store
    let layer3Store: Layer3Store
    let layer4Store: Layer4Store
    let layer5Store: Layer5Store
    let snapshotStore: SnapshotStore

    /// Export personality data in the specified format.
    func export(format: ExportFormat, language: String = currentResponseLanguage()) async throws -> Data {
        switch format {
        case .minimal, .card:
            let allTraits = try collectAllTraits()
            guard !allTraits.isEmpty else { throw ExportError.noData }
            let prompt = buildExportPrompt(traits: allTraits, format: format)
            let systemMsg = "You are a personality data summarization assistant.\n\nIMPORTANT: You MUST respond in \(language)."

            let (response, _) = try await AIFallbackClient.shared.chatCompletion(
                functionName: "chat",
                debugFunction: "personality_export"
            ) { slot in
                ChatCompletionRequest(
                    model: slot.modelName,
                    messages: [
                        .init(role: "system", content: [.text(systemMsg)]),
                        .init(role: "user", content: [.text(prompt)])
                    ],
                    temperature: 0.3,
                    responseFormat: nil
                )
            }
            let text = response.choices.first?.message.content ?? ""
            guard let data = text.data(using: .utf8) else { throw ExportError.encodingFailed }
            return data

        case .structuredJSON:
            let dto = try buildStructuredDTO()
            return try Self.prettyEncoder.encode(dto)

        case .fullArchive:
            let archive = try buildFullArchive()
            return try Self.prettyEncoder.encode(archive)
        }
    }

    // MARK: - Data Collection

    private func collectAllTraits() throws -> [String: [[String: String]]] {
        var result: [String: [[String: String]]] = [:]

        let l1 = try layer1Store.fetchTraits()
        if !l1.isEmpty {
            result["Behavioral Rhythms"] = l1.map { ["dimension": $0.dimension, "value": $0.value] }
        }

        let l2 = try layer2Store.fetchTraits()
        if !l2.isEmpty {
            result["Knowledge & Interests"] = l2.map { ["dimension": $0.dimension, "value": $0.value] }
        }

        let l3 = try layer3Store.fetchTraits()
        if !l3.isEmpty {
            result["Cognitive Style"] = l3.map {
                var d: [String: String] = ["dimension": $0.dimension, "value": $0.value]
                if let desc = $0.description { d["description"] = desc }
                return d
            }
        }

        let l4 = try layer4Store.fetchTraits()
        if !l4.isEmpty {
            result["Expression"] = l4.map { ["dimension": $0.dimension, "value": $0.value] }
        }

        let l5 = try layer5Store.fetchTraits()
        if !l5.isEmpty {
            result["Values"] = l5.map {
                var d: [String: String] = ["dimension": $0.dimension, "value": $0.value]
                if let desc = $0.description { d["description"] = desc }
                return d
            }
        }

        return result
    }

    private func buildExportPrompt(traits: [String: [[String: String]]], format: ExportFormat) -> String {
        let traitsText = traits.map { layer, items in
            let itemsStr = items.map {
                let base = "- \($0["dimension"] ?? ""): \($0["value"] ?? "")"
                if let desc = $0["description"], !desc.isEmpty {
                    return "\(base)（\(desc)）"
                }
                return base
            }.joined(separator: "\n")
            return "### \(layer)\n\(itemsStr)"
        }.joined(separator: "\n\n")

        switch format {
        case .minimal:
            return """
            Based on the following user personality data, generate a minimal plain-text description of approximately 200 tokens.
            Suitable for AI Custom Instructions. Write in second person.

            \(traitsText)
            """
        case .card:
            return """
            Based on the following user personality data, generate a Markdown-formatted personality card (approximately 500 tokens).
            Include: core personality, cognitive style, communication preferences, interest areas, values.
            Suitable for System Prompt / Chatbot presets.

            \(traitsText)
            """
        default:
            return ""
        }
    }

    // MARK: - Structured DTO

    struct PersonalityDTO: Codable {
        let version: String
        let exportDate: Date
        let layers: [String: [TraitDTO]]

        struct TraitDTO: Codable {
            let dimension: String
            let value: String
            let description: String?
            let confidence: Double
        }
    }

    private func buildStructuredDTO() throws -> PersonalityDTO {
        var layers: [String: [PersonalityDTO.TraitDTO]] = [:]

        let l1 = try layer1Store.fetchTraits()
        if !l1.isEmpty {
            layers["layer1_rhythms"] = l1.map { .init(dimension: $0.dimension, value: $0.value, description: nil, confidence: $0.confidence) }
        }
        let l2 = try layer2Store.fetchTraits()
        if !l2.isEmpty {
            layers["layer2_knowledge"] = l2.map { .init(dimension: $0.dimension, value: $0.value, description: nil, confidence: $0.confidence) }
        }
        let l3 = try layer3Store.fetchTraits()
        if !l3.isEmpty {
            layers["layer3_cognitive"] = l3.map { .init(dimension: $0.dimension, value: $0.value, description: $0.description, confidence: $0.confidence) }
        }
        let l4 = try layer4Store.fetchTraits()
        if !l4.isEmpty {
            layers["layer4_expression"] = l4.map { .init(dimension: $0.dimension, value: $0.value, description: nil, confidence: $0.confidence) }
        }
        let l5 = try layer5Store.fetchTraits()
        if !l5.isEmpty {
            layers["layer5_values"] = l5.map { .init(dimension: $0.dimension, value: $0.value, description: $0.description, confidence: $0.confidence) }
        }

        return PersonalityDTO(
            version: "1.0",
            exportDate: .now,
            layers: layers
        )
    }

    // MARK: - Full Archive

    struct FullArchive: Codable {
        let version: String
        let exportDate: Date
        let layers: [String: [TraitArchive]]
        let snapshots: [SnapshotArchive]?

        struct TraitArchive: Codable {
            let id: String
            let dimension: String
            let value: String
            let description: String?
            let confidence: Double
            let evidenceCount: Int?
            let firstObserved: Date?
            let lastUpdated: Date
            let version: Int?
        }

        struct SnapshotArchive: Codable {
            let id: String?
            let snapshotDate: Date
            let fullProfile: String?
            let summaryText: String?
            let trigger: String
        }
    }

    private func buildFullArchive() throws -> FullArchive {
        var layers: [String: [FullArchive.TraitArchive]] = [:]

        let l1 = try layer1Store.fetchTraits()
        layers["layer1"] = l1.map {
            .init(id: $0.id, dimension: $0.dimension, value: $0.value, description: nil,
                  confidence: $0.confidence, evidenceCount: $0.evidenceCount,
                  firstObserved: $0.firstObserved, lastUpdated: $0.lastUpdated, version: $0.version)
        }

        let l2 = try layer2Store.fetchTraits()
        layers["layer2"] = l2.map {
            .init(id: $0.id, dimension: $0.dimension, value: $0.value, description: nil,
                  confidence: $0.confidence, evidenceCount: nil,
                  firstObserved: nil, lastUpdated: $0.lastUpdated, version: $0.version)
        }

        let l3 = try layer3Store.fetchTraits()
        layers["layer3"] = l3.map {
            .init(id: $0.id, dimension: $0.dimension, value: $0.value, description: $0.description,
                  confidence: $0.confidence, evidenceCount: $0.evidenceCount,
                  firstObserved: $0.firstObserved, lastUpdated: $0.lastUpdated, version: $0.version)
        }

        let l4 = try layer4Store.fetchTraits()
        layers["layer4"] = l4.map {
            .init(id: $0.id, dimension: $0.dimension, value: $0.value, description: nil,
                  confidence: $0.confidence, evidenceCount: nil,
                  firstObserved: nil, lastUpdated: $0.lastUpdated, version: $0.version)
        }

        let l5 = try layer5Store.fetchTraits()
        layers["layer5"] = l5.map {
            .init(id: $0.id, dimension: $0.dimension, value: $0.value, description: $0.description,
                  confidence: $0.confidence, evidenceCount: $0.evidenceCount,
                  firstObserved: $0.firstObserved, lastUpdated: $0.lastUpdated, version: $0.version)
        }

        let snapshots = try? snapshotStore.fetchAll(limit: 50)
        let snapshotArchives = snapshots?.map {
            FullArchive.SnapshotArchive(
                id: $0.id,
                snapshotDate: $0.snapshotDate,
                fullProfile: $0.fullProfile,
                summaryText: $0.summaryText,
                trigger: $0.trigger
            )
        }

        return FullArchive(
            version: "1.0",
            exportDate: .now,
            layers: layers,
            snapshots: snapshotArchives
        )
    }

    // MARK: - Encoder

    private static var prettyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
