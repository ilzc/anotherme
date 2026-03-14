import Foundation

/// Layer 4: Expression style analysis. Collects writing samples and uses AI to analyze communication patterns.
enum Layer4Analyzer {

    /// Minimum text length to qualify as a writing sample.
    private static let minTextLength = 20

    /// Minimum number of text records needed before running analysis.
    private static let minSampleCount = 5

    /// Maximum number of samples to save per analysis batch.
    private static let maxSamplesPerBatch = 50

    /// Analyze activity records to extract expression style traits.
    static func analyze(
        records: [ActivityRecord],
        store: Layer4Store,
        aiClient: AIClient,
        onProgress: AnalysisProgressReport? = nil
    ) async throws {
        // 1. Collect text samples — prefer userAuthored and userExpressions (user's own text)
        await onProgress?("Collecting text samples…")
        var textRecords = records.filter { record in
            let authoredLen = (record.userAuthored ?? "").count
            let expressionsLen = record.userExpressions?.reduce(0, { $0 + $1.count }) ?? 0
            return (authoredLen + expressionsLen) > minTextLength
        }

        // Fallback: if too few user expression samples, supplement with extractedText
        // from chat/email contexts only (where text is more likely user-written)
        if textRecords.count < minSampleCount {
            let chatEmailContexts: Set<String> = ["work_chat", "email", "document"]
            let existingIds = Set(textRecords.map(\.id))
            let fallbackRecords = records.filter { record in
                let context = inferWritingContext(record)
                return chatEmailContexts.contains(context)
                    && (record.extractedText ?? "").count > minTextLength
                    && !existingIds.contains(record.id)
            }
            textRecords.append(contentsOf: fallbackRecords)
        }

        guard textRecords.count >= minSampleCount else {
            await onProgress?("Insufficient text samples (\(textRecords.count)/\(minSampleCount)), skipping analysis")
            return
        }

        // 2. Save writing samples (max 50 per batch)
        await onProgress?("Saving writing samples (\(min(textRecords.count, maxSamplesPerBatch)) records)")
        // Prioritize userExpressions (chat messages) as individual samples
        for record in textRecords.prefix(maxSamplesPerBatch) {
            let context = inferWritingContext(record)

            // Save each user expression as a separate sample (preserves individual message style)
            if let expressions = record.userExpressions?.filter({ $0.count >= 5 }), !expressions.isEmpty {
                for expression in expressions.prefix(5) {
                    let sample = WritingSample(
                        id: UUID().uuidString,
                        timestamp: record.timestamp,
                        context: context,
                        content: String(expression.prefix(500)),
                        sentiment: nil,
                        wordCount: countWords(expression)
                    )
                    try store.insertSample(sample)
                }
            }

            // Also save userAuthored as a sample
            let text = record.userAuthored ?? record.extractedText ?? ""
            guard text.count > minTextLength else { continue }
            let sample = WritingSample(
                id: UUID().uuidString,
                timestamp: record.timestamp,
                context: context,
                content: String(text.prefix(500)),
                sentiment: nil,
                wordCount: countWords(text)
            )
            try store.insertSample(sample)
        }

        // 3. AI analysis (skip if not configured)
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)
        guard config.isConfigured else {
            await onProgress?("AI not configured, skipping deep analysis")
            return
        }

        let recentSamples = try store.fetchRecentSamples(limit: 30)
        guard !recentSamples.isEmpty else {
            await onProgress?("No writing samples available for analysis")
            return
        }

        await onProgress?("Calling AI to analyze expression style (\(recentSamples.count) samples)…")
        let request = DeepAnalysisPrompt.buildLayer4Prompt(samples: recentSamples)
        let response = try await aiClient.chatCompletion(config: config, request: request, debugFunction: "layer4_expression")
        let traits = try DeepAnalysisPrompt.parseTraitsResponse(response)

        // 4. Upsert expression traits
        await onProgress?("Saving expression traits (\(traits.count) dimensions)")
        for trait in traits {
            try upsertExpressionTrait(
                store: store,
                dimension: trait.dimension,
                value: trait.value,
                confidence: trait.confidence
            )
        }

        // 5. Generate style guide (needs 20+ samples, throttle to once per 24h)
        await onProgress?("Checking style guide generation conditions…")
        try await generateStyleGuideIfNeeded(store: store, aiClient: aiClient, config: config, onProgress: onProgress)
    }

    // MARK: - Style Guide Generation

    private static let styleGuideMinSamples = 20

    private static func generateStyleGuideIfNeeded(
        store: Layer4Store,
        aiClient: AIClient,
        config: AIModelSlot,
        onProgress: AnalysisProgressReport?
    ) async throws {
        let totalSamples = try store.sampleCount()
        guard totalSamples >= styleGuideMinSamples else {
            await onProgress?("Skipping style guide (samples \(totalSamples)/\(styleGuideMinSamples) insufficient)")
            return
        }

        // Throttle: skip if style_anchor was updated within 24h
        let existingAnchor = try store.fetchTraits(dimension: "style_anchor")
        if let anchor = existingAnchor.first,
           -anchor.lastUpdated.timeIntervalSinceNow < 24 * 3600 {
            await onProgress?("Skipping style guide (updated within last 24 hours)")
            return
        }

        // Fetch more samples for style guide (up to 100)
        let samples = try store.fetchRecentSamples(limit: 100)
        guard !samples.isEmpty else { return }

        await onProgress?("Calling AI to generate style guide (\(samples.count) samples)…")
        let request = DeepAnalysisPrompt.buildStyleGuidePrompt(samples: samples)
        let response = try await aiClient.chatCompletion(config: config, request: request, debugFunction: "layer4_style_guide")
        let (anchor, diffs, examples) = try DeepAnalysisPrompt.parseStyleGuideResponse(response)

        // Store as 3 trait dimensions
        await onProgress?("Saving style guide (anchor + differentiators + examples)")
        let confidence = min(1.0, Double(totalSamples) / 100.0)
        try upsertExpressionTrait(store: store, dimension: "style_anchor", value: anchor, confidence: confidence)
        try upsertExpressionTrait(store: store, dimension: "key_differentiators", value: diffs, confidence: confidence)
        try upsertExpressionTrait(store: store, dimension: "curated_examples", value: examples, confidence: confidence)
    }

    // MARK: - Writing Context Inference

    /// Map appName/activityCategory to a writing context string.
    static func inferWritingContext(_ record: ActivityRecord) -> String {
        let app = record.appName.lowercased()
        let cat = record.activityCategory.lowercased()

        // Chat / messaging apps
        if app.contains("slack") || app.contains("discord") || app.contains("telegram") ||
           app.contains("wechat") || app.contains("微信") || app.contains("teams") ||
           app.contains("messages") || app.contains("信息") || app.contains("dingtalk") ||
           app.contains("飞书") || app.contains("feishu") || app.contains("lark") ||
           cat == "social" {
            return "work_chat"
        }

        // Email
        if app.contains("mail") || app.contains("outlook") || app.contains("邮件") {
            return "email"
        }

        // Code editors / IDEs
        if app.contains("xcode") || app.contains("vscode") || app.contains("visual studio") ||
           app.contains("intellij") || app.contains("sublime") || app.contains("vim") ||
           app.contains("cursor") || app.contains("terminal") || app.contains("iterm") ||
           app.contains("warp") {
            return "code_comment"
        }

        // Browsers
        if app.contains("safari") || app.contains("chrome") || app.contains("firefox") ||
           app.contains("edge") || app.contains("arc") || app.contains("brave") {
            return "browser"
        }

        // Document / writing apps
        if app.contains("pages") || app.contains("word") || app.contains("notion") ||
           app.contains("obsidian") || app.contains("bear") || app.contains("notes") ||
           app.contains("备忘录") || app.contains("typora") || app.contains("ulysses") ||
           cat == "creative" {
            return "document"
        }

        return "other"
    }

    // MARK: - Word Count

    /// Count words in text, handling both CJK and Latin text.
    private static func countWords(_ text: String) -> Int {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }

    // MARK: - Trait Upsert (Incremental)

    private static func upsertExpressionTrait(
        store: Layer4Store,
        dimension: String,
        value: String,
        confidence: Double
    ) throws {
        let existing = try store.fetchTraits(dimension: dimension)
        if var trait = existing.first {
            // Merge: weighted average favoring new data
            trait.value = value
            trait.confidence = (trait.confidence * 0.3 + confidence * 0.7)
            trait.lastUpdated = .now
            trait.version += 1
            try store.upsertTrait(trait)
        } else {
            let trait = ExpressionTrait(
                id: UUID().uuidString,
                dimension: dimension,
                value: value,
                confidence: confidence,
                lastUpdated: .now,
                version: 1
            )
            try store.upsertTrait(trait)
        }
    }
}
