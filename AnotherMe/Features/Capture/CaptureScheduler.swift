import Foundation
import AppKit

/// Manages the three capture modes and deduplication.
@Observable
@MainActor
final class CaptureScheduler {
    // MARK: - Configuration

    var intervalSeconds: Int = 300
    var eventDrivenEnabled: Bool = true
    var smartSamplingEnabled: Bool = true

    // MARK: - Callbacks

    var onCaptureTrigger: ((CaptureMode) -> Void)?

    // MARK: - Tunable Thresholds (defaults; override before calling startAll)

    /// Minimum seconds between any two captures, shared by all modes.
    /// Defaults to intervalSeconds; set via intervalSeconds setter.
    var minimumInterval: TimeInterval {
        TimeInterval(intervalSeconds)
    }

    /// Seconds to wait after an event before triggering a capture (debounce)
    var eventDebounceDelay: TimeInterval = 1.5

    /// How often (seconds) the smart-sampling timer checks activity level
    var smartCheckInterval: Int = 5

    // MARK: - State

    private(set) var isRunning = false
    private var lastCaptureTime: Date = .distantPast

    // Interval mode
    private var intervalTimer: DispatchSourceTimer?

    // Event-driven mode
    private var workspaceObservers: [NSObjectProtocol] = []
    private var debounceTask: Task<Void, Never>?
    let windowObserver = WindowObserver()

    // Smart sampling mode
    private let inputMonitor = InputActivityMonitor()
    private var smartTimer: DispatchSourceTimer?

    // MARK: - Start / Stop

    func startAll() {
        guard !isRunning else { return }
        isRunning = true

        // Interval timer always runs as the baseline capture mode.
        startIntervalMode()

        if eventDrivenEnabled {
            startEventDrivenMode()
        }
        if smartSamplingEnabled {
            startSmartSamplingMode()
        }
    }

    func stopAll() {
        isRunning = false
        stopIntervalMode()
        stopEventDrivenMode()
        stopSmartSamplingMode()
    }

    func recordCapture() {
        lastCaptureTime = .now
    }

    func shouldCapture() -> Bool {
        Date.now.timeIntervalSince(lastCaptureTime) >= minimumInterval
    }

    // MARK: - Interval Mode

    private func startIntervalMode() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(
            deadline: .now() + .seconds(intervalSeconds),
            repeating: .seconds(intervalSeconds)
        )
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.triggerCapture(mode: .interval)
            }
        }
        timer.resume()
        intervalTimer = timer
    }

    private func stopIntervalMode() {
        intervalTimer?.cancel()
        intervalTimer = nil
    }

    // MARK: - Event-Driven Mode

    private func startEventDrivenMode() {
        let center = NSWorkspace.shared.notificationCenter

        let appSwitch = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.triggerEventDriven() }
        }

        let spaceSwitch = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.triggerEventDriven() }
        }

        let screenWake = center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.triggerEventDriven() }
        }

        workspaceObservers = [appSwitch, spaceSwitch, screenWake]

        // Window title changes (browser tab switches, document changes)
        windowObserver.onWindowTitleChanged = { [weak self] in
            self?.triggerEventDriven()
        }
        windowObserver.start()
    }

    /// Debounce: wait 1.5s after event before capturing,
    /// so fast Cmd+Tab switching only triggers once.
    private func triggerEventDriven() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(eventDebounceDelay))
            guard !Task.isCancelled else { return }
            triggerCapture(mode: .event)
        }
    }

    private func stopEventDrivenMode() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
        windowObserver.stop()
    }

    // MARK: - Smart Sampling Mode

    private func startSmartSamplingMode() {
        guard inputMonitor.start() else {
            // Accessibility permission not available, skip smart sampling
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + .seconds(smartCheckInterval), repeating: .seconds(smartCheckInterval))
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.evaluateSmartCapture()
            }
        }
        timer.resume()
        smartTimer = timer
    }

    /// Check activity level and decide whether to capture
    private var lastSmartCaptureTime: Date = .distantPast

    private func evaluateSmartCapture() {
        let level = inputMonitor.activityLevel

        // Smart sampling uses minimumInterval as the active floor.
        // Idle and deepIdle scale up from there.
        let interval: TimeInterval
        switch level {
        case .active:   interval = minimumInterval          // Respect user setting
        case .idle:     interval = minimumInterval * 3      // 3x when idle
        case .deepIdle: return                              // Don't capture when deeply idle
        }

        let elapsed = Date.now.timeIntervalSince(lastSmartCaptureTime)
        if elapsed >= interval {
            lastSmartCaptureTime = .now
            triggerCapture(mode: .smart)
        }
    }

    private func stopSmartSamplingMode() {
        smartTimer?.cancel()
        smartTimer = nil
        inputMonitor.stop()
    }

    // MARK: - Common

    private func triggerCapture(mode: CaptureMode) {
        guard shouldCapture() else { return }
        onCaptureTrigger?(mode)
    }
}
