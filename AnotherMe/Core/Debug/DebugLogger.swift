import Foundation

// MARK: - DebugLogEntry

struct DebugLogEntry: Identifiable, Comparable, Hashable {
    let id: String          // filename
    let timestamp: Date
    let category: Category
    let functionName: String  // e.g. "screenshot_analysis", "layer3_cognitive", "chat"
    let filePath: URL       // full path to the file

    enum Category: String, CaseIterable {
        case capture = "Capture"
        case llm = "LLM Call"
        case stored = "Stored"
    }

    static func < (lhs: DebugLogEntry, rhs: DebugLogEntry) -> Bool {
        lhs.timestamp > rhs.timestamp  // newest first
    }
}

// MARK: - Live Request Tracking

/// A tracked LLM request with status, for real-time display in debug UI.
@Observable
final class TrackedRequest: Identifiable, Hashable {
    static func == (lhs: TrackedRequest, rhs: TrackedRequest) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: String
    let function: String
    let model: String
    let endpoint: String
    let startTime: Date
    var status: Status = .pending
    var durationMs: Int?
    var responsePreview: String?
    var tokenUsage: (prompt: Int, completion: Int, total: Int)?
    var errorMessage: String?
    var requestMessages: [(role: String, preview: String)] = []

    enum Status: String {
        case pending = "Pending"
        case completed = "Completed"
        case error = "Error"
    }

    init(id: String = UUID().uuidString, function: String, model: String, endpoint: String) {
        self.id = id
        self.function = function
        self.model = model
        self.endpoint = endpoint
        self.startTime = .now
    }
}

/// Central debug logger for development mode.
/// When enabled, logs screenshots, LLM requests/responses, and stored data
/// to ~/Library/Application Support/AnotherMe/DebugLogs/<session>/
final class DebugLogger: @unchecked Sendable {
    static let shared = DebugLogger()

    /// UserDefaults key for dev mode toggle
    static let enabledKey = "debug.devMode.enabled"

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Live tracked requests (newest first). Observable for SwiftUI binding.
    @MainActor var trackedRequests: [TrackedRequest] = []
    private let maxTrackedRequests = 200

    private let baseDir: URL
    private let dateFormatter: DateFormatter
    private let isoFormatter: ISO8601DateFormatter
    private var sessionDir: URL?
    private let queue = DispatchQueue(label: "com.anotherme.debuglogger")

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDir = appSupport.appendingPathComponent("AnotherMe/DebugLogs", isDirectory: true)

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss_SSS"

        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    // MARK: - Session Management

    /// Start a new debug session (call at app launch or when dev mode is toggled on).
    func startSession() {
        guard isEnabled else { return }
        let sessionName = DateFormatter.localizedString(from: .now, dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        let dir = baseDir.appendingPathComponent(sessionName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sessionDir = dir
    }

    // MARK: - Live Request Tracking

    /// Create a tracked request entry before making the LLM call.
    func trackRequestStart(
        function: String,
        model: String,
        endpoint: String,
        messages: [ChatCompletionRequest.Message]
    ) -> String {
        let tracked = TrackedRequest(function: function, model: model, endpoint: endpoint)
        tracked.requestMessages = messages.map { msg in
            let preview: String
            if let textContent = msg.content.first(where: { $0.type == "text" })?.text {
                preview = String(textContent.prefix(2000))
            } else if msg.content.contains(where: { $0.type == "image_url" }) {
                preview = "[Image]"
            } else {
                preview = ""
            }
            return (role: msg.role, preview: preview)
        }
        DispatchQueue.main.async { [weak self] in
            self?.trackedRequests.insert(tracked, at: 0)
            if let self, self.trackedRequests.count > self.maxTrackedRequests {
                self.trackedRequests.removeLast(self.trackedRequests.count - self.maxTrackedRequests)
            }
        }
        return tracked.id
    }

    /// Update a tracked request with success result.
    func trackRequestComplete(
        id: String,
        durationMs: Int,
        response: ChatCompletionResponse
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let tracked = self?.trackedRequests.first(where: { $0.id == id }) else { return }
            tracked.status = .completed
            tracked.durationMs = durationMs
            tracked.responsePreview = response.choices.first?.message.content.map { String($0.prefix(3000)) }
            if let usage = response.usage {
                tracked.tokenUsage = (usage.promptTokens, usage.completionTokens, usage.totalTokens)
            }
        }
    }

    /// Update a tracked request with error.
    func trackRequestError(id: String, durationMs: Int, error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let tracked = self?.trackedRequests.first(where: { $0.id == id }) else { return }
            tracked.status = .error
            tracked.durationMs = durationMs
            tracked.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Screenshot Logging

    /// Save a captured screenshot as JPEG file.
    func logScreenshot(imageBase64: String, mode: String, screenIndex: Int) {
        guard isEnabled, let dir = currentDir() else { return }
        queue.async {
            let ts = self.timestamp()
            let filename = "\(ts)_capture_screen\(screenIndex)_\(mode).jpg"
            let fileURL = dir.appendingPathComponent(filename)
            if let data = Data(base64Encoded: imageBase64) {
                try? data.write(to: fileURL)
            }
        }
    }

    // MARK: - LLM Call Logging

    /// Log an LLM request and response pair.
    func logLLMCall(
        function: String,
        model: String,
        endpoint: String,
        request: ChatCompletionRequest,
        response: ChatCompletionResponse?,
        error: Error?,
        durationMs: Int
    ) {
        guard isEnabled, let dir = currentDir() else { return }
        queue.async {
            let ts = self.timestamp()
            let filename = "\(ts)_llm_\(function).json"
            let fileURL = dir.appendingPathComponent(filename)

            // Build messages without image base64 (too large)
            let messagesForLog = request.messages.map { msg -> [String: Any] in
                let contents: [[String: Any]] = msg.content.map { c in
                    if c.type == "image_url" {
                        return ["type": "image_url", "image_url": "(base64 omitted, see capture screenshot)"]
                    } else {
                        return ["type": "text", "text": c.text ?? ""]
                    }
                }
                return ["role": msg.role, "content": contents]
            }

            var entry: [String: Any] = [
                "timestamp": self.isoFormatter.string(from: .now),
                "function": function,
                "model": model,
                "endpoint": endpoint,
                "duration_ms": durationMs,
                "request": [
                    "model": request.model,
                    "temperature": request.temperature,
                    "response_format": request.responseFormat?.type ?? "none",
                    "messages": messagesForLog,
                ] as [String: Any],
            ]

            if let response {
                let choices = response.choices.map { choice -> [String: Any] in
                    ["content": choice.message.content ?? "(nil)"]
                }
                var respDict: [String: Any] = ["choices": choices]
                if let usage = response.usage {
                    respDict["usage"] = [
                        "prompt_tokens": usage.promptTokens,
                        "completion_tokens": usage.completionTokens,
                        "total_tokens": usage.totalTokens,
                    ]
                }
                entry["response"] = respDict
            }

            if let error {
                entry["error"] = "\(error)"
            }

            if let data = try? JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: fileURL)
            }
        }
    }

    // MARK: - Stored Data Logging

    /// Log what was saved to the local database after analysis.
    func logStoredRecord(function: String, record: Any) {
        guard isEnabled, let dir = currentDir() else { return }
        queue.async {
            let ts = self.timestamp()
            let filename = "\(ts)_stored_\(function).json"
            let fileURL = dir.appendingPathComponent(filename)

            var dict: [String: Any] = [
                "timestamp": self.isoFormatter.string(from: .now),
                "function": function,
            ]

            // Try Encodable first, fall back to String description
            if let encodable = record as? Encodable,
               let data = try? JSONEncoder().encode(AnyEncodable(encodable)),
               let json = try? JSONSerialization.jsonObject(with: data) {
                dict["data"] = json
            } else {
                dict["data"] = "\(record)"
            }

            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: fileURL)
            }
        }
    }

    // MARK: - Log Directory Info

    /// Returns the current session's log directory path (for display in UI).
    var logDirectoryPath: String? {
        currentDir()?.path
    }

    /// Total size of all debug logs in bytes.
    var totalLogSize: Int64 {
        guard FileManager.default.fileExists(atPath: baseDir.path) else { return 0 }
        let enumerator = FileManager.default.enumerator(at: baseDir, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Delete all debug logs.
    func clearAllLogs() {
        try? FileManager.default.removeItem(at: baseDir)
    }

    // MARK: - Reading Log Entries (for UI)

    /// Scan the current session directory and return structured entries parsed from filenames.
    func loadEntries() -> [DebugLogEntry] {
        guard let dir = sessionDir else { return [] }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        let parser = DateFormatter()
        parser.dateFormat = "yyyyMMdd_HHmmss_SSS"

        var entries: [DebugLogEntry] = []
        for fileURL in contents {
            let filename = fileURL.lastPathComponent
            guard let entry = parseFilename(filename, at: fileURL, using: parser) else { continue }
            entries.append(entry)
        }
        return entries.sorted()
    }

    /// Read and parse a JSON file for an LLM log entry.
    func loadLLMDetail(entry: DebugLogEntry) -> [String: Any]? {
        guard entry.category == .llm else { return nil }
        return loadJSON(at: entry.filePath)
    }

    /// Read the raw JPEG data for a capture entry.
    func loadScreenshotData(entry: DebugLogEntry) -> Data? {
        guard entry.category == .capture else { return nil }
        return try? Data(contentsOf: entry.filePath)
    }

    /// Read and parse a JSON file for a stored-record entry.
    func loadStoredDetail(entry: DebugLogEntry) -> [String: Any]? {
        guard entry.category == .stored else { return nil }
        return loadJSON(at: entry.filePath)
    }

    // MARK: - Private (Read Helpers)

    private func loadJSON(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Parse a debug-log filename into a `DebugLogEntry`, or return nil if unrecognised.
    private func parseFilename(_ filename: String, at fileURL: URL, using parser: DateFormatter) -> DebugLogEntry? {
        // Expected patterns:
        //   YYYYMMDD_HHmmss_SSS_capture_<function>.jpg
        //   YYYYMMDD_HHmmss_SSS_llm_<function>.json
        //   YYYYMMDD_HHmmss_SSS_stored_<function>.json
        // The timestamp portion occupies the first 19 characters: "yyyyMMdd_HHmmss_SSS"

        guard filename.count > 20 else { return nil }
        let tsString = String(filename.prefix(19))
        guard let timestamp = parser.date(from: tsString) else { return nil }

        // After the timestamp there is an underscore, then category_function.ext
        let remainder = String(filename.dropFirst(20)) // drop "YYYYMMDD_HHmmss_SSS_"

        let category: DebugLogEntry.Category
        let afterCategory: String

        if remainder.hasPrefix("capture_") {
            category = .capture
            afterCategory = String(remainder.dropFirst("capture_".count))
        } else if remainder.hasPrefix("llm_") {
            category = .llm
            afterCategory = String(remainder.dropFirst("llm_".count))
        } else if remainder.hasPrefix("stored_") {
            category = .stored
            afterCategory = String(remainder.dropFirst("stored_".count))
        } else {
            return nil
        }

        // Strip extension to get the function name
        let functionName: String
        if let dotIndex = afterCategory.lastIndex(of: ".") {
            functionName = String(afterCategory[afterCategory.startIndex..<dotIndex])
        } else {
            functionName = afterCategory
        }

        return DebugLogEntry(
            id: filename,
            timestamp: timestamp,
            category: category,
            functionName: functionName,
            filePath: fileURL
        )
    }

    // MARK: - Private

    private func currentDir() -> URL? {
        if sessionDir == nil { startSession() }
        return sessionDir
    }

    private func timestamp() -> String {
        dateFormatter.string(from: .now)
    }
}

// MARK: - Type-erased Encodable wrapper

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        _encode = { encoder in
            try wrapped.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
