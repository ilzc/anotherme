import Foundation

// MARK: - Model Provider (reusable model endpoint config)

struct AIModelProvider: Codable, Identifiable, Equatable {
    let id: String
    var displayName: String
    var endpoint: String
    var apiKey: String
    var modelName: String
    var customHeaders: [String: String]

    var isConfigured: Bool {
        !endpoint.isEmpty && !apiKey.isEmpty && !modelName.isEmpty
    }

    init(
        id: String = UUID().uuidString,
        displayName: String = "",
        endpoint: String = "",
        apiKey: String = "",
        modelName: String = "",
        customHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelName = modelName
        self.customHeaders = customHeaders
    }
}

// MARK: - Function Slot Assignment

struct AIFunctionAssignment: Codable {
    var providerIDs: [String]
    var temperature: Double

    /// Backward-compatible computed property: gets/sets the first provider ID.
    var providerID: String? {
        get { providerIDs.first }
        set {
            if let id = newValue {
                if providerIDs.isEmpty {
                    providerIDs = [id]
                } else {
                    providerIDs[0] = id
                }
            } else {
                if !providerIDs.isEmpty {
                    providerIDs.removeFirst()
                }
            }
        }
    }

    init(providerIDs: [String] = [], temperature: Double = 0.1) {
        self.providerIDs = providerIDs
        self.temperature = temperature
    }

    /// Backward-compatible convenience init (requires explicit providerID argument)
    init(providerID: String?, temperature: Double = 0.1) {
        if let id = providerID {
            self.providerIDs = [id]
        } else {
            self.providerIDs = []
        }
        self.temperature = temperature
    }

    // MARK: - Codable (backward compatibility)

    enum CodingKeys: String, CodingKey {
        case providerIDs
        case providerID  // legacy single-value key
        case temperature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.1

        // Try new format first
        if let ids = try container.decodeIfPresent([String].self, forKey: .providerIDs) {
            self.providerIDs = ids
        } else if let singleID = try container.decodeIfPresent(String.self, forKey: .providerID) {
            // Migrate from old single-value format
            self.providerIDs = [singleID]
        } else {
            self.providerIDs = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerIDs, forKey: .providerIDs)
        try container.encode(temperature, forKey: .temperature)
    }
}

// MARK: - Resolved Slot (used by consumers)

struct AIModelSlot: Codable, Identifiable {
    var id: String { name }

    let name: String
    var endpoint: String
    var apiKey: String
    var modelName: String
    var temperature: Double
    var customHeaders: [String: String]

    var isConfigured: Bool {
        !endpoint.isEmpty && !apiKey.isEmpty && !modelName.isEmpty
    }

    init(
        name: String,
        endpoint: String = "",
        apiKey: String = "",
        modelName: String = "",
        temperature: Double = 0.1,
        customHeaders: [String: String] = [:]
    ) {
        self.name = name
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelName = modelName
        self.temperature = temperature
        self.customHeaders = customHeaders
    }

    /// For identification in fallback chain
    var providerID: String { name }

    // MARK: - Predefined Function Slots

    static let screenshotAnalysis = "screenshot_analysis"
    static let deepAnalysis = "deep_analysis"
    static let router = "router"
    static let chat = "chat"
    static let embedding = "embedding"

    static let allFunctions: [(name: String, label: String, recommendedType: String, recommendedModels: String, defaultTemperature: Double)] = [
        (screenshotAnalysis, "Screenshot Analysis", "Vision/Multimodal", "gpt-4o-mini / gemini-2.0-flash", 0.1),
        (deepAnalysis, "Deep Analysis", "Large Reasoning Model", "claude-sonnet / gpt-4o", 0.1),
        (router, "Intent Router", "Flash/Lightweight Model", "gemini-2.0-flash / haiku", 0.0),
        (chat, "Chat", "Large Chat Model", "claude-sonnet / gpt-4o", 0.7),
        (embedding, "Embedding", "Embedding Model", "text-embedding-3-small", 0.0),
    ]
}
