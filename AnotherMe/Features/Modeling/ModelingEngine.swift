import Foundation

/// Orchestrates the full modeling pipeline across all 5 personality layers.
/// All layers use AI-assisted analysis. A personality snapshot is generated at the end.
actor ModelingEngine {
    private let activityStore: ActivityStore
    private let layer1Store: Layer1Store
    private let layer2Store: Layer2Store
    private let layer3Store: Layer3Store
    private let layer4Store: Layer4Store
    private let layer5Store: Layer5Store
    private let snapshotStore: SnapshotStore
    private let aiClient: AIClient

    enum Status: Sendable {
        case idle
        case running(layer: Int, progress: String)
        case completed(Date)
        case failed(String)
    }

    private(set) var status: Status = .idle

    init(
        activityStore: ActivityStore,
        layer1Store: Layer1Store,
        layer2Store: Layer2Store,
        layer3Store: Layer3Store,
        layer4Store: Layer4Store,
        layer5Store: Layer5Store,
        snapshotStore: SnapshotStore,
        aiClient: AIClient
    ) {
        self.activityStore = activityStore
        self.layer1Store = layer1Store
        self.layer2Store = layer2Store
        self.layer3Store = layer3Store
        self.layer4Store = layer4Store
        self.layer5Store = layer5Store
        self.snapshotStore = snapshotStore
        self.aiClient = aiClient
    }

    // MARK: - Debug: Force Run with Progress Tracking

    /// Force-run a specific layer (or all) using ALL activity records, ignoring thresholds.
    /// Reports detailed progress to the provided ForceAnalysisState.
    func forceRunLayer(_ layer: Int, state: ForceAnalysisState) async throws {
        // Re-entrancy guard
        if case .running = status { throw ForceRunError.alreadyRunning }

        status = .running(layer: layer, progress: "Force analysis…")

        do {
            // Fetch all records
            let tenYearsAgo = Calendar.current.date(byAdding: .year, value: -10, to: .now) ?? .now
            let records = try activityStore.fetch(from: tenYearsAgo, to: .now)

            await MainActor.run {
                state.recordCount = records.count
                state.log("Fetched \(records.count) activity records", layer: 0)
            }

            guard !records.isEmpty else {
                status = .failed("No activity records")
                await MainActor.run { state.finish() }
                throw ForceRunError.noRecords
            }

            let layersToRun = layer == 0 ? [1, 2, 3, 4, 5] : [layer]

            for l in layersToRun {
                try Task.checkCancellation()
                let layerStart = Date()

                // Progress callback for this layer
                let progressCallback: AnalysisProgressReport = { [state] step in
                    await MainActor.run { state.updateStep(step, layer: l) }
                }

                do {
                    switch l {
                    case 1:
                        await MainActor.run { state.startLayer(1, step: "Analyzing behavioral rhythm…") }
                        status = .running(layer: 1, progress: "Analyzing behavioral rhythm…")
                        try await Layer1Analyzer.analyze(
                            records: records, store: layer1Store,
                            aiClient: aiClient, onProgress: progressCallback
                        )
                        await MainActor.run { state.completeLayer(1, startTime: layerStart) }

                    case 2:
                        await MainActor.run { state.startLayer(2, step: "Building knowledge graph…") }
                        status = .running(layer: 2, progress: "Building knowledge graph…")
                        try await Layer2Analyzer.analyze(
                            records: records, store: layer2Store,
                            aiClient: aiClient, onProgress: progressCallback
                        )
                        await MainActor.run { state.completeLayer(2, startTime: layerStart) }

                    case 3:
                        await MainActor.run { state.startLayer(3, step: "Analyzing cognitive style…") }
                        status = .running(layer: 3, progress: "Analyzing cognitive style…")
                        try await Layer3Analyzer.analyze(
                            records: records, store: layer3Store,
                            aiClient: aiClient, onProgress: progressCallback
                        )
                        await MainActor.run { state.completeLayer(3, startTime: layerStart) }

                    case 4:
                        await MainActor.run { state.startLayer(4, step: "Analyzing expression style…") }
                        status = .running(layer: 4, progress: "Analyzing expression style…")
                        try await Layer4Analyzer.analyze(
                            records: records, store: layer4Store,
                            aiClient: aiClient, onProgress: progressCallback
                        )
                        await MainActor.run { state.completeLayer(4, startTime: layerStart) }

                    case 5:
                        await MainActor.run { state.startLayer(5, step: "Inferring values…") }
                        status = .running(layer: 5, progress: "Inferring values…")
                        try await Layer5Analyzer.analyze(
                            records: records, store: layer5Store,
                            aiClient: aiClient,
                            layer1Store: layer1Store, layer2Store: layer2Store,
                            onProgress: progressCallback
                        )
                        await MainActor.run { state.completeLayer(5, startTime: layerStart) }

                    default:
                        break
                    }
                } catch is CancellationError {
                    await MainActor.run { state.skipLayer(l, reason: "Cancelled") }
                    throw CancellationError()
                } catch {
                    await MainActor.run { state.failLayer(l, error: error.localizedDescription) }
                    throw error
                }
            }

            // Snapshot when running all layers
            if layer == 0 {
                try Task.checkCancellation()
                let snapshotStart = Date()
                await MainActor.run { state.log("Generating personality snapshot…", layer: 0) }
                status = .running(layer: 0, progress: "Generating personality snapshot…")
                try await SnapshotGenerator.generate(
                    trigger: .manual,
                    stores: (layer1Store, layer2Store, layer3Store, layer4Store, layer5Store),
                    snapshotStore: snapshotStore,
                    aiClient: aiClient
                )
                let dur = Date().timeIntervalSince(snapshotStart)
                await MainActor.run {
                    state.log("Personality snapshot generated (\(String(format: "%.1f", dur))s)", layer: 0, level: .success)
                }
            }

            status = .completed(Date())
            await MainActor.run { state.finish() }
        } catch is CancellationError {
            status = .idle
            await MainActor.run { state.finish() }
        } catch let error as ForceRunError {
            await MainActor.run { state.finish() }
            throw error
        } catch {
            status = .failed(error.localizedDescription)
            await MainActor.run { state.finish() }
            throw error
        }
    }

    enum ForceRunError: LocalizedError {
        case alreadyRunning
        case noRecords

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: "Modeling engine is already running"
            case .noRecords: "No activity records available for analysis"
            }
        }
    }

    // MARK: - Production: Full Analysis Pipeline

    func runFullAnalysis(trigger: ModelingScheduler.TriggerReason) async {
        // Re-entrancy guard: skip if already running
        if case .running = status { return }

        status = .running(layer: 0, progress: "Fetching data for analysis…")

        do {
            let records = try activityStore.fetchUnanalyzed(limit: 5000)
            guard !records.isEmpty else {
                status = .completed(Date())
                return
            }

            // Layer 1 (AI-assisted)
            try Task.checkCancellation()
            status = .running(layer: 1, progress: "Analyzing behavioral rhythm…")
            try await Layer1Analyzer.analyze(records: records, store: layer1Store, aiClient: aiClient)

            // Layer 2 (AI-assisted)
            try Task.checkCancellation()
            status = .running(layer: 2, progress: "Building knowledge graph…")
            try await Layer2Analyzer.analyze(records: records, store: layer2Store, aiClient: aiClient)

            // Layer 3 (AI-assisted)
            try Task.checkCancellation()
            status = .running(layer: 3, progress: "Analyzing cognitive style…")
            try await Layer3Analyzer.analyze(records: records, store: layer3Store, aiClient: aiClient)

            // Layer 4 (AI-assisted)
            try Task.checkCancellation()
            status = .running(layer: 4, progress: "Analyzing expression style…")
            try await Layer4Analyzer.analyze(records: records, store: layer4Store, aiClient: aiClient)

            // Layer 5 (AI-assisted, cross-layer)
            try Task.checkCancellation()
            status = .running(layer: 5, progress: "Inferring values…")
            try await Layer5Analyzer.analyze(
                records: records,
                store: layer5Store,
                aiClient: aiClient,
                layer1Store: layer1Store,
                layer2Store: layer2Store
            )

            // Generate personality snapshot
            try Task.checkCancellation()
            status = .running(layer: 0, progress: "Generating personality snapshot…")
            try await SnapshotGenerator.generate(
                trigger: trigger,
                stores: (layer1Store, layer2Store, layer3Store, layer4Store, layer5Store),
                snapshotStore: snapshotStore,
                aiClient: aiClient
            )

            // Mark analyzed
            let ids = records.map(\.id)
            try activityStore.markAnalyzed(ids: ids)

            status = .completed(Date())
        } catch is CancellationError {
            status = .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
