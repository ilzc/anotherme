import Foundation

/// Progress callback type for analyzers to report sub-step progress.
typealias AnalysisProgressReport = @Sendable (String) async -> Void

/// Observable state for force analysis progress tracking.
/// Provides per-layer status, live logs, elapsed time, and overall progress.
@MainActor
@Observable
final class ForceAnalysisState {
    static let shared = ForceAnalysisState()

    var isRunning = false
    var targetLayers: [Int] = []
    var completedLayers: Set<Int> = []
    var currentLayer: Int = 0
    var currentStep: String = ""
    var layerStatuses: [Int: LayerStatus] = [:]
    var logs: [LogEntry] = []
    var startTime: Date?
    var recordCount: Int = 0
    private(set) var task: Task<Void, Never>?

    enum LayerStatus {
        case pending
        case running(step: String)
        case completed(duration: TimeInterval)
        case failed(String)
        case skipped(String)

        var isTerminal: Bool {
            switch self {
            case .completed, .failed, .skipped: true
            default: false
            }
        }
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let layer: Int
        let message: String
        let level: Level

        enum Level { case info, success, warning, error }
    }

    var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var overallProgress: Double {
        guard !targetLayers.isEmpty else { return 0 }
        return Double(completedLayers.count) / Double(targetLayers.count)
    }

    func reset(layers: [Int]) {
        isRunning = true
        targetLayers = layers
        completedLayers = []
        currentLayer = 0
        currentStep = ""
        layerStatuses = Dictionary(uniqueKeysWithValues: layers.map { ($0, LayerStatus.pending) })
        logs = []
        startTime = Date()
        recordCount = 0
    }

    func setTask(_ task: Task<Void, Never>) {
        self.task = task
    }

    func log(_ message: String, layer: Int, level: LogEntry.Level = .info) {
        logs.append(LogEntry(timestamp: Date(), layer: layer, message: message, level: level))
    }

    func startLayer(_ layer: Int, step: String) {
        currentLayer = layer
        currentStep = step
        layerStatuses[layer] = .running(step: step)
        log(step, layer: layer)
    }

    func updateStep(_ step: String, layer: Int) {
        currentStep = step
        layerStatuses[layer] = .running(step: step)
        log(step, layer: layer)
    }

    func completeLayer(_ layer: Int, startTime: Date) {
        let duration = Date().timeIntervalSince(startTime)
        layerStatuses[layer] = .completed(duration: duration)
        completedLayers.insert(layer)
        log("Completed (\(String(format: "%.1f", duration))s)", layer: layer, level: .success)
    }

    func failLayer(_ layer: Int, error: String) {
        layerStatuses[layer] = .failed(error)
        log("Failed: \(error)", layer: layer, level: .error)
    }

    func skipLayer(_ layer: Int, reason: String) {
        layerStatuses[layer] = .skipped(reason)
        completedLayers.insert(layer)
        log("Skipped: \(reason)", layer: layer, level: .warning)
    }

    func finish() {
        isRunning = false
        currentStep = ""
        task = nil
    }

    func cancel() {
        task?.cancel()
        isRunning = false
        currentStep = ""
        log("Analysis cancelled by user", layer: currentLayer, level: .warning)
        // Mark remaining pending layers as skipped
        for layer in targetLayers {
            if case .pending = layerStatuses[layer] {
                layerStatuses[layer] = .skipped("Cancelled")
            } else if case .running = layerStatuses[layer] {
                layerStatuses[layer] = .skipped("Cancelled")
            }
        }
        task = nil
    }
}
