import Foundation
import UserNotifications

/// Tracks consecutive AI failures and sends system notifications.
final class AIFailureNotifier: @unchecked Sendable {
    static let shared = AIFailureNotifier()

    private var consecutiveFailures: [String: Int] = [:]
    private let pauseThreshold = 3
    private let lock = NSLock()

    private init() {}

    /// Record a failure for a function. Returns true if auto-paused (3+ consecutive).
    @discardableResult
    func recordFailure(function: String, error: AIClientError) -> Bool {
        lock.lock()
        let count = (consecutiveFailures[function] ?? 0) + 1
        consecutiveFailures[function] = count
        lock.unlock()

        // Send notification on first failure
        if count == 1 {
            sendNotification(for: error)
        }

        // Auto-pause after threshold
        if count >= pauseThreshold {
            print("[AIFailureNotifier] \(function): \(count) consecutive failures, auto-paused")
            return true
        }
        return false
    }

    func recordSuccess(function: String) {
        lock.lock()
        defer { lock.unlock() }
        consecutiveFailures[function] = 0
    }

    func isPaused(function: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (consecutiveFailures[function] ?? 0) >= pauseThreshold
    }

    func resetPause(function: String) {
        lock.lock()
        defer { lock.unlock() }
        consecutiveFailures[function] = 0
    }

    private func sendNotification(for error: AIClientError) {
        let content = UNMutableNotificationContent()
        content.title = "AnotherMe"

        switch error {
        case .unauthorized:
            content.body = "Invalid API key. Please check settings."
        case .rateLimited:
            content.body = "Rate limited. Will retry shortly."
        case .networkError, .requestTimeout:
            content.body = "Network error. Please check your connection."
        case .notConfigured:
            content.body = "AI model not configured. Go to Settings."
        default:
            content.body = "AI analysis error"
        }

        let request = UNNotificationRequest(
            identifier: "ai_failure_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
