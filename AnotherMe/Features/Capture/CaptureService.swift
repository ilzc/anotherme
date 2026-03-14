import Foundation
import AppKit
import ScreenCaptureKit

extension Notification.Name {
    /// Posted by CaptureService after each successful capture cycle.
    static let captureCompleted = Notification.Name("AnotherMe.captureCompleted")
}

/// Main capture orchestrator.
/// Coordinates screen capture, animation feedback, and analysis pipeline.
/// Integrates the Phase 3 gate pipeline: system state → hard block → soft filter → capture → pixel dedup → AI analysis.
@Observable
@MainActor
final class CaptureService {
    private let screenProvider = ScreenProvider()
    private let scheduler = CaptureScheduler()
    private let animationWindow = CaptureAnimationWindow()
    private let analysisPipeline: AnalysisPipeline

    // Phase 3 pipeline components
    private let screenState = ScreenStateMonitor()
    private let securityFilter = SecurityFilter()
    /// Per-display deduplicators so that multi-monitor setups compare each
    /// display against its own previous frame (not cross-display).
    private var deduplicators: [Int: ImageDeduplicator] = [:]

    private func deduplicator(for displayIndex: Int) -> ImageDeduplicator {
        if let existing = deduplicators[displayIndex] {
            return existing
        }
        let new = ImageDeduplicator()
        deduplicators[displayIndex] = new
        return new
    }

    private(set) var isRunning = false
    private(set) var todayCaptureCount = 0
    private var dailyResetDate: Date = .distantPast
    private var screenResumedObserver: NSObjectProtocol?

    init(analysisPipeline: AnalysisPipeline) {
        self.analysisPipeline = analysisPipeline
    }

    // MARK: - Configuration

    struct Config {
        var intervalSeconds: Int = 300
        var eventDrivenEnabled: Bool = true
        var smartSamplingEnabled: Bool = true
        var showAnimation: Bool = true
        var selectedDisplayIndices: Set<Int> = [0] // Default: main screen only
        var dailyLimit: Int = 200  // Max AI analysis calls per day
    }

    func start(config: Config) {
        guard !isRunning else { return }

        scheduler.intervalSeconds = config.intervalSeconds
        scheduler.eventDrivenEnabled = config.eventDrivenEnabled
        scheduler.smartSamplingEnabled = config.smartSamplingEnabled

        scheduler.onCaptureTrigger = { [weak self] mode in
            guard let self else { return }
            Task { await self.performCapture(mode: mode, config: config) }
        }

        // Observe screen resume to trigger immediate capture
        screenResumedObserver = NotificationCenter.default.addObserver(
            forName: .screenResumed, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.performCapture(mode: .event, config: config)
            }
        }

        scheduler.startAll()
        isRunning = true
    }

    func stop() {
        scheduler.stopAll()
        scheduler.onCaptureTrigger = nil
        if let observer = screenResumedObserver {
            NotificationCenter.default.removeObserver(observer)
            screenResumedObserver = nil
        }
        isRunning = false
    }

    // MARK: - Capture (Gate Pipeline)

    @MainActor
    private func performCapture(mode: CaptureMode, config: Config) async {
        guard scheduler.shouldCapture() else { return }

        // Reset daily counter at midnight
        resetDailyCountIfNeeded()

        // ── Gate 1: System state (global — all modes) ──
        guard screenState.canCapture else { return }
        if screenState.checkAndResetIdleState() { return }

        // ── Gate 2: Hard block (SecureInput + blacklist) ──
        let blockResult = securityFilter.shouldBlockCapture()
        switch blockResult {
        case .blocked:
            return
        case .blockedWithMetadata(let app):
            print("[CaptureService] Hard-blocked: \(app), recording metadata only")
            // TODO: Persist metadata per TDD §3.5 — requires ActivityStore.insertMetadataOnly()
            // ActivityStore.shared.insertMetadataOnly(appName: app, timestamp: .now)
            return
        case .allowed:
            break
        }

        // ── Gate 3: Soft filter (context-aware keyword check) ──
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let windowTitle = scheduler.windowObserver.currentWindowTitle() ?? ""
        if securityFilter.shouldSkipAnalysis(windowTitle: windowTitle, appBundleID: bundleID) {
            print("[CaptureService] Soft-filtered: \(windowTitle)")
            return
        }

        // ── Capture ──
        do {
            let displays = try await screenProvider.availableDisplays()
            var capturedAny = false

            for (index, display) in displays.enumerated() {
                guard config.selectedDisplayIndices.contains(index) else { continue }

                // ── Daily limit check (before expensive capture call) ──
                guard todayCaptureCount < config.dailyLimit else {
                    print("[CaptureService] Daily limit reached (\(config.dailyLimit))")
                    break
                }

                let image = try await screenProvider.captureScreen(display: display)

                // ── Gate 4: Pixel deduplication (per-display) ──
                guard deduplicator(for: index).hasChanged(image) else {
                    screenState.reportPixelUnchanged()
                    continue
                }
                screenState.reportPixelChanged()

                // Show animation feedback
                if config.showAnimation {
                    animationWindow.playAnimation()
                }

                // Convert to base64 and enqueue for analysis
                if let base64 = ScreenProvider.imageToBase64(image) {
                    await analysisPipeline.enqueue(
                        imageBase64: base64,
                        mode: mode,
                        screenIndex: index
                    )
                    todayCaptureCount += 1
                    capturedAny = true
                } else {
                    print("[CaptureService] imageToBase64 returned nil for display \(index)")
                }
            }

            // Only record capture timestamp if something was actually enqueued,
            // so that dedup-only cycles don't suppress the next real capture.
            if capturedAny {
                scheduler.recordCapture()
                NotificationCenter.default.post(name: .captureCompleted, object: nil)
            }
        } catch {
            handleCaptureError(error)
        }
    }

    private func resetDailyCountIfNeeded() {
        let today = Calendar.current.startOfDay(for: .now)
        if dailyResetDate < today {
            todayCaptureCount = 0
            dailyResetDate = today
        }
    }

    private func handleCaptureError(_ error: Error) {
        print("[CaptureService] Capture failed: \(error.localizedDescription)")
        print("[CaptureService] Error details: \(error)")

        // Post a notification so the UI can show an error indicator if needed
        NotificationCenter.default.post(
            name: .captureCompleted,
            object: nil,
            userInfo: ["error": error]
        )
    }
}
