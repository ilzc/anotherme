import Foundation
import AppKit
import CoreGraphics

// MARK: - Notification

extension Notification.Name {
    /// Posted when the screen resumes from lock or screensaver.
    /// `CaptureScheduler` can observe this to trigger an immediate capture.
    static let screenResumed = Notification.Name("AnotherMe.screenResumed")
}

// MARK: - ScreenStateMonitor

/// Unified monitor for screen lock, screensaver, and system idle state.
///
/// Used as Gate 1 in the capture pipeline to skip captures when the user
/// is away (locked screen, screensaver active, or prolonged inactivity).
@Observable
@MainActor
final class ScreenStateMonitor {

    // MARK: - Published State

    private(set) var isScreenLocked = false
    private(set) var isScreenSaverActive = false

    // MARK: - Pixel-Unchanged Tracking

    /// Number of consecutive capture cycles where the screen pixels did not change.
    private var consecutiveUnchangedCount = 0

    // MARK: - Thresholds

    /// Seconds of no user input before considering idle (used together with pixel check).
    private let idleInputThreshold: TimeInterval = 180

    /// Number of consecutive unchanged frames required (in addition to input idle) to declare system idle.
    private let idleUnchangedThreshold = 3

    // MARK: - Notification Observers

    private var observers: [NSObjectProtocol] = []

    // MARK: - Computed Properties

    /// Whether capture is allowed from a screen-state perspective.
    /// Returns `false` when the screen is locked or the screensaver is active.
    var canCapture: Bool {
        !isScreenLocked && !isScreenSaverActive
    }

    /// Comprehensive idle determination: no user input beyond threshold AND
    /// screen pixels have been unchanged for several consecutive cycles.
    ///
    /// Call `checkSystemIdle()` instead of reading this directly when you need
    /// the side-effect of resetting the unchanged counter on input resumption.
    var isSystemIdle: Bool {
        let idleSeconds = secondsSinceLastUserInput()
        return idleSeconds > idleInputThreshold && consecutiveUnchangedCount >= idleUnchangedThreshold
    }

    /// Checks system idle state and resets the unchanged counter if the user
    /// has resumed input. This solves the chicken-and-egg problem where being
    /// idle prevents captures, which in turn prevents the counter from being reset.
    ///
    /// Use this method in the capture pipeline (Gate 1) instead of reading
    /// `isSystemIdle` directly, so the side-effect is explicit.
    func checkAndResetIdleState() -> Bool {
        let idleSeconds = secondsSinceLastUserInput()
        // Auto-reset when input resumes
        if idleSeconds < idleInputThreshold {
            consecutiveUnchangedCount = 0
        }
        return idleSeconds > idleInputThreshold && consecutiveUnchangedCount >= idleUnchangedThreshold
    }

    // MARK: - Init

    init() {
        registerNotifications()
    }

    /// Call to unregister notifications before the monitor is discarded.
    /// (deinit cannot access MainActor-isolated properties directly.)
    func tearDown() {
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - Pixel Change Reporting

    /// Called by the capture pipeline (Gate 4) when the latest frame is
    /// identical to the previous one.
    func reportPixelUnchanged() {
        consecutiveUnchangedCount += 1
    }

    /// Called by the capture pipeline (Gate 4) when the latest frame differs
    /// from the previous one.
    func reportPixelChanged() {
        consecutiveUnchangedCount = 0
    }

    // MARK: - User Input Idle Query

    /// Returns the number of seconds since the most recent user input event
    /// across multiple event types. The minimum value is returned so that
    /// *any* recent input counts as "not idle".
    private func secondsSinceLastUserInput() -> Double {
        let types: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .keyDown,
            .scrollWheel
        ]
        return types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? .infinity
    }

    // MARK: - Private — Notification Registration

    private func registerNotifications() {
        let center = DistributedNotificationCenter.default()

        // Screen lock
        let lockObserver = center.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isScreenLocked = true
            }
        }

        // Screen unlock
        let unlockObserver = center.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isScreenLocked = false
                self?.postScreenResumed()
            }
        }

        // Screensaver started
        let screensaverStartObserver = center.addObserver(
            forName: .init("com.apple.screensaver.didStart"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isScreenSaverActive = true
            }
        }

        // Screensaver stopped
        let screensaverStopObserver = center.addObserver(
            forName: .init("com.apple.screensaver.didStop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isScreenSaverActive = false
                self?.postScreenResumed()
            }
        }

        observers = [lockObserver, unlockObserver, screensaverStartObserver, screensaverStopObserver]
    }

    /// Notify the rest of the app that the screen is available again.
    /// Also resets the idle counter so that the first capture after resume
    /// is not blocked by stale idle state (e.g. Touch ID unlock produces
    /// no CGEvent, so secondsSinceLastUserInput may still be large).
    private func postScreenResumed() {
        consecutiveUnchangedCount = 0
        NotificationCenter.default.post(name: .screenResumed, object: nil)
    }
}
