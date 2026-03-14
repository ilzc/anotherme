import Foundation

/// Manages AI model providers and function-to-provider assignments.
/// API keys go to Keychain, other config goes to UserDefaults.
final class AIModelSlotStore: @unchecked Sendable {
    static let shared = AIModelSlotStore()

    private let defaults = UserDefaults.standard
    private let keychain = KeychainManager.shared

    private let providersKey = "ai.providers"
    private let assignmentsKey = "ai.assignments"

    private init() {}

    // MARK: - Provider CRUD

    func loadProviders() -> [AIModelProvider] {
        guard let data = defaults.data(forKey: providersKey),
              var providers = try? JSONDecoder().decode([AIModelProvider].self, from: data) else {
            return []
        }
        // Inject API keys from Keychain
        for i in providers.indices {
            providers[i].apiKey = keychain.getAPIKey(for: "provider.\(providers[i].id)") ?? ""
        }
        return providers
    }

    func saveProviders(_ providers: [AIModelProvider]) {
        // Save API keys to Keychain separately
        for provider in providers {
            if !provider.apiKey.isEmpty {
                try? keychain.saveAPIKey(provider.apiKey, for: "provider.\(provider.id)")
            }
        }
        // Strip API keys before saving to UserDefaults
        var stripped = providers
        for i in stripped.indices {
            stripped[i].apiKey = ""
        }
        if let data = try? JSONEncoder().encode(stripped) {
            defaults.set(data, forKey: providersKey)
        }
    }

    func saveProvider(_ provider: AIModelProvider) {
        var providers = loadProviders()
        if let idx = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[idx] = provider
        } else {
            providers.append(provider)
        }
        saveProviders(providers)
    }

    func deleteProvider(id: String) {
        var providers = loadProviders()
        providers.removeAll { $0.id == id }
        saveProviders(providers)
        try? keychain.deleteAPIKey(for: "provider.\(id)")

        // Remove this provider from any assignments' providerIDs list
        var assignments = loadAssignments()
        for key in assignments.keys {
            assignments[key]?.providerIDs.removeAll { $0 == id }
        }
        saveAssignments(assignments)
    }

    func loadProvider(id: String) -> AIModelProvider? {
        loadProviders().first { $0.id == id }
    }

    // MARK: - Function Assignments

    func loadAssignments() -> [String: AIFunctionAssignment] {
        guard let data = defaults.data(forKey: assignmentsKey),
              let assignments = try? JSONDecoder().decode([String: AIFunctionAssignment].self, from: data) else {
            return [:]
        }
        return assignments
    }

    func saveAssignments(_ assignments: [String: AIFunctionAssignment]) {
        if let data = try? JSONEncoder().encode(assignments) {
            defaults.set(data, forKey: assignmentsKey)
        }
    }

    func saveAssignment(_ assignment: AIFunctionAssignment, for functionName: String) {
        var assignments = loadAssignments()
        assignments[functionName] = assignment
        saveAssignments(assignments)
    }

    func loadAssignment(for functionName: String) -> AIFunctionAssignment {
        loadAssignments()[functionName] ?? AIFunctionAssignment(providerIDs: [])
    }

    // MARK: - Resolved Slot

    /// Load a resolved AIModelSlot for a function name.
    /// Combines the assigned provider's connection info with per-function parameters.
    /// Uses the first providerID from the ordered list.
    func load(name: String) -> AIModelSlot {
        let assignment = loadAssignment(for: name)
        guard let providerID = assignment.providerIDs.first,
              let provider = loadProvider(id: providerID) else {
            return AIModelSlot(name: name)
        }
        return AIModelSlot(
            name: name,
            endpoint: provider.endpoint,
            apiKey: provider.apiKey,
            modelName: provider.modelName,
            temperature: assignment.temperature,
            customHeaders: provider.customHeaders
        )
    }

    /// Load all configured fallback slots for a function name, in priority order.
    func loadFallbackSlots(name: String) -> [AIModelSlot] {
        let assignment = loadAssignment(for: name)
        return assignment.providerIDs.compactMap { providerID in
            guard let provider = loadProvider(id: providerID),
                  provider.isConfigured else { return nil }
            return AIModelSlot(
                name: name,
                endpoint: provider.endpoint,
                apiKey: provider.apiKey,
                modelName: provider.modelName,
                temperature: assignment.temperature,
                customHeaders: provider.customHeaders
            )
        }
    }

}
