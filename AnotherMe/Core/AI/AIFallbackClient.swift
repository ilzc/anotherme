import Foundation

/// Wraps AIClient with ordered fallback across multiple providers.
/// Does NOT replace AIClient — it's a higher-level orchestrator.
final class AIFallbackClient: @unchecked Sendable {
    static let shared = AIFallbackClient()

    private let client = AIClient.shared
    private let store = AIModelSlotStore.shared

    /// Cooldown tracking for providers that failed with unauthorized
    private var cooldownUntil: [String: Date] = [:]
    private let cooldownDuration: TimeInterval = 1800 // 30 minutes
    private let lock = NSLock()

    private init() {}

    /// Execute a chat completion with fallback across configured providers.
    /// Returns the response and the slot that succeeded.
    func chatCompletion(
        functionName: String,
        debugFunction: String? = nil,
        requestBuilder: (AIModelSlot) -> ChatCompletionRequest
    ) async throws -> (ChatCompletionResponse, AIModelSlot) {
        guard !AIFailureNotifier.shared.isPaused(function: functionName) else {
            throw AIClientError.rateLimited
        }

        let slots = store.loadFallbackSlots(name: functionName)
            .filter { !isInCooldown($0) }
        guard !slots.isEmpty else { throw AIClientError.notConfigured }

        var lastError: Error = AIClientError.notConfigured

        for slot in slots {
            do {
                let response = try await client.chatCompletion(
                    config: slot,
                    request: requestBuilder(slot),
                    debugFunction: debugFunction ?? functionName
                )
                AIFailureNotifier.shared.recordSuccess(function: functionName)
                return (response, slot)
            } catch let error as AIClientError {
                lastError = error
                if error.shouldFallback {
                    if case .unauthorized = error {
                        setCooldown(for: slot)
                    }
                    print("[AIFallbackClient] \(functionName) failed on provider, trying next: \(error.errorDescription ?? "")")
                    continue
                } else {
                    throw error
                }
            }
        }
        if let aiError = lastError as? AIClientError {
            AIFailureNotifier.shared.recordFailure(function: functionName, error: aiError)
        }
        throw lastError
    }

    // MARK: - Cooldown

    private func cooldownKey(for slot: AIModelSlot) -> String {
        // Use endpoint + first 8 chars of API key as unique provider identifier
        slot.endpoint + "." + String(slot.apiKey.prefix(8))
    }

    private func isInCooldown(_ slot: AIModelSlot) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let until = cooldownUntil[cooldownKey(for: slot)] else { return false }
        return Date.now < until
    }

    private func setCooldown(for slot: AIModelSlot) {
        lock.lock()
        defer { lock.unlock() }
        cooldownUntil[cooldownKey(for: slot)] = Date.now.addingTimeInterval(cooldownDuration)
    }
}
