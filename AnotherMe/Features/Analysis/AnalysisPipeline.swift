import Foundation

/// Manages the queue of screenshots waiting for AI analysis.
/// Processes one at a time, with retry and backoff.
actor AnalysisPipeline {
    private let aiClient: AIClient
    private let activityStore: ActivityStore
    private var memoryExtractor: MemoryExtractor?
    private var queue: [CaptureItem] = []
    private var isProcessing = false
    private let maxQueueSize = 20

    struct CaptureItem {
        let imageBase64: String
        let timestamp: Date
        let mode: CaptureMode
        let screenIndex: Int
    }

    // MARK: - Status (observable from outside the actor)

    enum Status: Sendable {
        case idle
        case processing
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var processedCount: Int = 0
    private(set) var errorCount: Int = 0

    init(aiClient: AIClient = .shared, activityStore: ActivityStore, memoryExtractor: MemoryExtractor? = nil) {
        self.aiClient = aiClient
        self.activityStore = activityStore
        self.memoryExtractor = memoryExtractor
    }

    func setMemoryExtractor(_ extractor: MemoryExtractor) {
        self.memoryExtractor = extractor
    }

    // MARK: - Enqueue

    func enqueue(imageBase64: String, mode: CaptureMode, screenIndex: Int) {
        let item = CaptureItem(
            imageBase64: imageBase64,
            timestamp: .now,
            mode: mode,
            screenIndex: screenIndex
        )

        // Debug: save screenshot image
        DebugLogger.shared.logScreenshot(
            imageBase64: imageBase64,
            mode: mode.rawValue,
            screenIndex: screenIndex
        )

        if queue.count >= maxQueueSize {
            print("[AnalysisPipeline] Queue overflow (\(queue.count)/\(maxQueueSize)): dropping oldest item")
            queue.removeFirst()
        }
        queue.append(item)

        if !isProcessing {
            processNext()
        }
    }

    // MARK: - Processing

    private func processNext() {
        guard !queue.isEmpty else {
            status = .idle
            return
        }

        isProcessing = true
        status = .processing
        let item = queue.removeFirst()

        Task {
            defer {
                isProcessing = false
                processNext()
            }
            await processItem(item)
        }
    }

    private func processItem(_ item: CaptureItem) async {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.screenshotAnalysis)

        guard config.isConfigured else {
            status = .error("Screenshot analysis model not configured")
            DebugLogger.shared.logStoredRecord(function: "screenshot_analysis_skipped", record: ["reason": "model_not_configured", "slot": AIModelSlot.screenshotAnalysis])
            return
        }

        do {
            let analysis = try await analyzeWithRetry(
                imageBase64: item.imageBase64,
                config: config,
                maxRetries: 2
            )

            // Validate / sanitize AI response
            let validCategories: Set<String> = [
                "work", "entertainment", "social", "learning",
                "finance", "creative", "system", "other"
            ]
            let sanitizedAppName = analysis.appName.isEmpty ? "Unknown" : analysis.appName
            let sanitizedCategory = validCategories.contains(analysis.activityCategory)
                ? analysis.activityCategory : "other"
            let sanitizedTopics = Array(analysis.topics.prefix(8))

            let validEngagement: Set<String> = ["deep_focus", "active_work", "browsing", "idle"]
            let sanitizedEngagement = analysis.engagementLevel.flatMap {
                validEngagement.contains($0) ? $0 : nil
            }

            let record = ActivityRecord(
                appName: sanitizedAppName,
                windowTitle: analysis.windowTitle,
                extractedText: analysis.extractedText?.combined,
                contentSummary: analysis.contentSummary,
                userIntent: analysis.userIntent,
                activityCategory: sanitizedCategory,
                topics: sanitizedTopics,
                screenIndex: item.screenIndex,
                captureMode: item.mode,
                visibleApps: analysis.visibleApps,
                userAuthored: analysis.extractedText?.userAuthored,
                userExpressions: analysis.extractedText?.userExpressions?.filter { !$0.isEmpty },
                engagementLevel: sanitizedEngagement
            )

            try activityStore.insert(record)
            processedCount += 1
            status = .idle

            // Extract memories from the analysis
            if let extractor = memoryExtractor {
                extractor.extractAndStore(from: analysis, activityId: record.id.uuidString)
            }

            // Debug: log what was stored
            DebugLogger.shared.logStoredRecord(function: "activity_record", record: record)

        } catch let error as AIClientError {
            handleAIError(error)
        } catch {
            errorCount += 1
            status = .error(error.localizedDescription)
        }
    }

    private func analyzeWithRetry(
        imageBase64: String,
        config: AIModelSlot,
        maxRetries: Int
    ) async throws -> ScreenshotAnalysis {
        var lastError: Error?

        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = pow(2.0, Double(attempt)) * 2.5 // 5s, 10s
                try await Task.sleep(for: .seconds(delay))
            }
            do {
                return try await aiClient.analyzeScreenshot(
                    imageBase64: imageBase64,
                    config: config
                )
            } catch AIClientError.rateLimited {
                lastError = AIClientError.rateLimited
                continue
            } catch AIClientError.serverError(let code) {
                lastError = AIClientError.serverError(code)
                continue
            } catch let urlError as URLError where [
                .timedOut, .networkConnectionLost, .notConnectedToInternet
            ].contains(urlError.code) {
                lastError = urlError
                continue
            } catch {
                throw error // Don't retry other errors
            }
        }

        throw lastError ?? AIClientError.serverError(500)
    }

    private func handleAIError(_ error: AIClientError) {
        errorCount += 1
        switch error {
        case .unauthorized:
            status = .error("Invalid API key. Check configuration.")
        case .rateLimited:
            status = .error("Rate limited. Auto-retry shortly.")
        default:
            status = .error(error.localizedDescription)
        }
    }
}
