import Foundation

enum ImportError: Error, LocalizedError {
    case invalidFormat
    case versionMismatch(String)
    case decodingFailed(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Unsupported import format"
        case .versionMismatch(let v): return "Incompatible version: \(v)"
        case .decodingFailed(let e): return "Decoding failed: \(e.localizedDescription)"
        case .noData: return "No data in archive"
        }
    }
}

enum ImportStrategy: String, CaseIterable, Identifiable {
    case overwrite = "Overwrite existing data"
    case merge = "Merge (keep higher confidence)"
    case missingOnly = "Import missing dimensions only"

    var id: String { rawValue }
}

/// Imports personality data from a full archive.
struct PersonalityImporter {

    /// Validate an archive file and return its metadata.
    static func validate(_ data: Data) throws -> PersonalityExporter.FullArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let archive = try decoder.decode(PersonalityExporter.FullArchive.self, from: data)
            guard archive.version == "1.0" else {
                throw ImportError.versionMismatch(archive.version)
            }
            return archive
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.decodingFailed(error)
        }
    }

    /// Import a validated archive with the specified strategy.
    /// Returns the number of traits imported/updated.
    @discardableResult
    static func importArchive(
        _ archive: PersonalityExporter.FullArchive,
        strategy: ImportStrategy,
        layer1Store: Layer1Store,
        layer2Store: Layer2Store,
        layer3Store: Layer3Store,
        layer4Store: Layer4Store,
        layer5Store: Layer5Store,
        snapshotStore: SnapshotStore? = nil
    ) throws -> Int {
        var count = 0

        print("[PersonalityImporter] Importing \(archive.layers.count) layers with strategy: \(strategy.rawValue)")

        // For overwrite strategy, clear existing data first
        if strategy == .overwrite {
            try layer1Store.deleteAll()
            try layer2Store.deleteAll()
            try layer3Store.deleteAll()
            try layer4Store.deleteAll()
            try layer5Store.deleteAll()
            if let snapshotStore {
                try snapshotStore.deleteAll()
            }
        }

        // Load existing traits once per layer (used by merge and missingOnly)
        let existingByLayer: [String: [String: Double]]
        if strategy != .overwrite {
            existingByLayer = [
                "layer1": Self.existingTraitMap(try? layer1Store.fetchTraits()),
                "layer2": Self.existingTraitMap(try? layer2Store.fetchTraits()),
                "layer3": Self.existingTraitMap(try? layer3Store.fetchTraits()),
                "layer4": Self.existingTraitMap(try? layer4Store.fetchTraits()),
                "layer5": Self.existingTraitMap(try? layer5Store.fetchTraits()),
            ]
        } else {
            existingByLayer = [:]
        }

        for (layerKey, traits) in archive.layers {
            let existing = existingByLayer[layerKey] ?? [:]

            for trait in traits {
                let shouldImport: Bool
                switch strategy {
                case .overwrite:
                    shouldImport = true
                case .missingOnly:
                    shouldImport = existing[trait.dimension] == nil
                case .merge:
                    let existingConf = existing[trait.dimension]
                    shouldImport = (existingConf == nil) || (trait.confidence > (existingConf ?? 0))
                }

                guard shouldImport else { continue }

                do {
                    switch layerKey {
                    case "layer1":
                        try layer1Store.upsertTrait(RhythmTrait(
                            id: trait.id, dimension: trait.dimension, value: trait.value,
                            confidence: trait.confidence,
                            evidenceCount: trait.evidenceCount ?? 0,
                            firstObserved: trait.firstObserved ?? trait.lastUpdated,
                            lastUpdated: trait.lastUpdated,
                            version: trait.version ?? 1
                        ))
                    case "layer2":
                        try layer2Store.upsertTrait(KnowledgeTrait(
                            id: trait.id, dimension: trait.dimension, value: trait.value,
                            confidence: trait.confidence,
                            lastUpdated: trait.lastUpdated,
                            version: trait.version ?? 1
                        ))
                    case "layer3":
                        try layer3Store.upsertTrait(CognitiveTrait(
                            id: trait.id, dimension: trait.dimension, value: trait.value,
                            description: trait.description,
                            confidence: trait.confidence,
                            evidenceCount: trait.evidenceCount ?? 0,
                            firstObserved: trait.firstObserved ?? trait.lastUpdated,
                            lastUpdated: trait.lastUpdated,
                            version: trait.version ?? 1
                        ))
                    case "layer4":
                        try layer4Store.upsertTrait(ExpressionTrait(
                            id: trait.id, dimension: trait.dimension, value: trait.value,
                            confidence: trait.confidence,
                            lastUpdated: trait.lastUpdated,
                            version: trait.version ?? 1
                        ))
                    case "layer5":
                        try layer5Store.upsertTrait(ValueTrait(
                            id: trait.id, dimension: trait.dimension, value: trait.value,
                            description: trait.description,
                            confidence: trait.confidence,
                            evidenceCount: trait.evidenceCount ?? 0,
                            firstObserved: trait.firstObserved ?? trait.lastUpdated,
                            lastUpdated: trait.lastUpdated,
                            version: trait.version ?? 1
                        ))
                    default:
                        print("[PersonalityImporter] Unknown layer key: \(layerKey)")
                        continue
                    }
                    count += 1
                } catch {
                    print("[PersonalityImporter] Failed to import \(layerKey)/\(trait.dimension): \(error)")
                }
            }
        }

        // Import snapshots if available and store provided
        if let snapshotStore, let snapshots = archive.snapshots, !snapshots.isEmpty {
            for snapshot in snapshots {
                do {
                    try snapshotStore.insert(PersonalitySnapshot(
                        id: snapshot.id ?? UUID().uuidString,
                        snapshotDate: snapshot.snapshotDate,
                        fullProfile: snapshot.fullProfile ?? "{}",
                        summaryText: snapshot.summaryText,
                        trigger: snapshot.trigger
                    ))
                    count += 1
                } catch {
                    print("[PersonalityImporter] Failed to import snapshot: \(error)")
                }
            }
        }

        print("[PersonalityImporter] Imported \(count) items")
        return count
    }

    // MARK: - Helpers

    /// Build a dimension -> confidence map from a trait array.
    private static func existingTraitMap<T: HasDimensionAndConfidence>(_ traits: [T]?) -> [String: Double] {
        guard let traits else { return [:] }
        return Dictionary(traits.map { ($0.dimension, $0.confidence) }, uniquingKeysWith: { _, latest in latest })
    }
}

/// Shared protocol for traits that have dimension and confidence fields.
protocol HasDimensionAndConfidence {
    var dimension: String { get }
    var confidence: Double { get }
}

extension RhythmTrait: HasDimensionAndConfidence {}
extension KnowledgeTrait: HasDimensionAndConfidence {}
extension CognitiveTrait: HasDimensionAndConfidence {}
extension ExpressionTrait: HasDimensionAndConfidence {}
extension ValueTrait: HasDimensionAndConfidence {}
