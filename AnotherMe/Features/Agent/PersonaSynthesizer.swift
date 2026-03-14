import Foundation

/// Synthesizes a narrative persona description from structured trait data.
/// Follows the OpenClaw SOUL.md paradigm: narrative text > structured traits.
/// The narrative is cached and regenerated when traits change significantly.
final class PersonaSynthesizer: Sendable {

    private let layer3Store: Layer3Store
    private let layer4Store: Layer4Store
    private let layer5Store: Layer5Store
    private let aiClient: AIClient

    /// UserDefaults keys for cached narrative.
    private static let narrativeKey = "persona.narrative"
    private static let narrativeTimestampKey = "persona.narrative.timestamp"
    private static let narrativeTraitHashKey = "persona.narrative.traitHash"

    /// UserDefaults keys for cached style guide.
    private static let styleGuideKey = "persona.styleGuide"
    private static let styleGuideTimestampKey = "persona.styleGuide.timestamp"
    private static let styleGuideTraitHashKey = "persona.styleGuide.traitHash"

    /// Maximum age before re-synthesis (24 hours).
    private static let maxAge: TimeInterval = 24 * 60 * 60

    init(
        layer3Store: Layer3Store,
        layer4Store: Layer4Store,
        layer5Store: Layer5Store,
        aiClient: AIClient = .shared
    ) {
        self.layer3Store = layer3Store
        self.layer4Store = layer4Store
        self.layer5Store = layer5Store
        self.aiClient = aiClient
    }

    // MARK: - Public API

    /// Returns a cached narrative if fresh, otherwise synthesizes a new one.
    /// Returns nil if no trait data is available (cold start).
    func fetchOrGenerate(language: String = currentResponseLanguage()) async throws -> String? {
        let (traits3, traits4, traits5) = try await loadTraits()

        // Cold start: no traits at all
        guard !traits3.isEmpty || !traits4.isEmpty || !traits5.isEmpty else {
            return nil
        }

        // Include language in hash so cache invalidates on language change
        let baseHash = computeTraitHash(l3: traits3, l4: traits4, l5: traits5)
        let currentHash = baseHash + "|lang:" + language

        // Check cache
        if let cached = loadCached(), cached.traitHash == currentHash {
            return cached.narrative
        }

        // Synthesize new narrative
        let narrative = try await synthesize(l3: traits3, l4: traits4, l5: traits5, language: language)
        saveCached(narrative: narrative, traitHash: currentHash)
        return narrative
    }

    /// Returns a cached style guide if fresh, otherwise distills a new one from L4 data.
    /// Returns nil if no L4 ExpressionTrait data is available.
    func fetchOrGenerateStyleGuide(language: String = currentResponseLanguage()) async throws -> String? {
        let traits4 = try await loadL4Traits()

        // No L4 data — nothing to distill
        guard !traits4.isEmpty else {
            return nil
        }

        // Include language in hash so cache invalidates on language change
        let baseHash = computeStyleGuideTraitHash(l4: traits4)
        let currentHash = baseHash + "|lang:" + language

        // Check cache
        if let cached = loadCachedStyleGuide(), cached.traitHash == currentHash {
            return cached.styleGuide
        }

        // Distill new style guide
        let styleGuide = try await distillStyleGuide(l4: traits4, language: language)
        saveCachedStyleGuide(styleGuide: styleGuide, traitHash: currentHash)
        return styleGuide
    }

    // MARK: - Trait Loading

    private func loadL4Traits() async throws -> [ExpressionTrait] {
        try await Task.detached {
            try self.layer4Store.fetchTraits()
        }.value
    }

    private func loadTraits() async throws -> ([CognitiveTrait], [ExpressionTrait], [ValueTrait]) {
        try await Task.detached {
            let l3 = try self.layer3Store.fetchTraits()
            let l4 = try self.layer4Store.fetchTraits()
            let l5 = try self.layer5Store.fetchTraits()
            return (l3, l4, l5)
        }.value
    }

    // MARK: - Synthesis

    private func synthesize(
        l3: [CognitiveTrait],
        l4: [ExpressionTrait],
        l5: [ValueTrait],
        language: String = currentResponseLanguage()
    ) async throws -> String {
        let inputText = buildSynthesisInput(l3: l3, l4: l4, l5: l5)
        let prompt = Self.synthesisPrompt + languageDirective(language)

        let (response, _) = try await AIFallbackClient.shared.chatCompletion(
            functionName: AIModelSlot.deepAnalysis,
            debugFunction: "persona_synthesis"
        ) { slot in
            ChatCompletionRequest(
                model: slot.modelName,
                messages: [
                    .init(role: "system", content: [.text(prompt)]),
                    .init(role: "user", content: [.text(inputText)])
                ],
                temperature: 0.3,
                responseFormat: nil
            )
        }

        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw AIClientError.emptyResponse
        }

        return content
    }

    private func buildSynthesisInput(
        l3: [CognitiveTrait],
        l4: [ExpressionTrait],
        l5: [ValueTrait]
    ) -> String {
        var sections: [String] = []

        // L3: Cognitive traits — use description (human-readable) when available
        if !l3.isEmpty {
            let lines = l3.filter { $0.confidence >= 0.5 }.map { trait -> String in
                if let desc = trait.description { return "- \(desc)" }
                return "- \(Self.cognitiveLabel(trait.dimension))：\(trait.value)"
            }
            sections.append("## This person's thinking style\n\(lines.joined(separator: "\n"))")
        }

        // L4: Expression — style anchor + key traits + real quotes
        if !l4.isEmpty {
            var lines: [String] = []
            if let anchor = l4.first(where: { $0.dimension == "style_anchor" })?.value {
                lines.append("Overall style: \(anchor)")
            }
            if let diffsJSON = l4.first(where: { $0.dimension == "key_differentiators" })?.value,
               let data = diffsJSON.data(using: .utf8),
               let diffs = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                for diff in diffs {
                    lines.append("- \(diff["trait"] ?? "")：\(diff["pattern"] ?? "")")
                }
            }
            // Real user quotes — the most valuable signal
            if let exJSON = l4.first(where: { $0.dimension == "curated_examples" })?.value,
               let data = exJSON.data(using: .utf8),
               let examples = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                lines.append("\nReal quotes from this person:")
                for ex in examples.prefix(10) {
                    let text = ex["text"] ?? ""
                    lines.append("「\(text)」")
                }
            }
            sections.append("## This person's communication style\n\(lines.joined(separator: "\n"))")
        }

        // L5: Value traits — use description when available
        if !l5.isEmpty {
            let lines = l5.filter { $0.confidence >= 0.5 }.map { trait -> String in
                if let desc = trait.description { return "- \(desc)" }
                return "- \(Self.valueLabel(trait.dimension))：\(trait.value)"
            }
            sections.append("## This person's values and priorities\n\(lines.joined(separator: "\n"))")
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Style Distillation

    private func distillStyleGuide(l4: [ExpressionTrait], language: String = currentResponseLanguage()) async throws -> String {
        let inputText = buildStyleDistillationInput(l4: l4)
        let prompt = Self.styleDistillationPrompt + languageDirective(language)

        let (response, _) = try await AIFallbackClient.shared.chatCompletion(
            functionName: AIModelSlot.deepAnalysis,
            debugFunction: "style_distillation"
        ) { slot in
            ChatCompletionRequest(
                model: slot.modelName,
                messages: [
                    .init(role: "system", content: [.text(prompt)]),
                    .init(role: "user", content: [.text(inputText)])
                ],
                temperature: 0.3,
                responseFormat: nil
            )
        }

        guard let content = response.choices.first?.message.content, !content.isEmpty else {
            throw AIClientError.emptyResponse
        }

        return content
    }

    private func buildStyleDistillationInput(l4: [ExpressionTrait]) -> String {
        var lines: [String] = []

        // Key differentiators
        if let diffsJSON = l4.first(where: { $0.dimension == "key_differentiators" })?.value,
           let data = diffsJSON.data(using: .utf8),
           let diffs = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            lines.append("## Expression traits")
            for diff in diffs {
                lines.append("- \(diff["trait"] ?? "")：\(diff["pattern"] ?? "")")
            }
        }

        // Curated examples
        if let exJSON = l4.first(where: { $0.dimension == "curated_examples" })?.value,
           let data = exJSON.data(using: .utf8),
           let examples = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            lines.append("\n## Real speech samples")
            for ex in examples.prefix(10) {
                let text = ex["text"] ?? ""
                lines.append("「\(text)」")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Labels (fallback when description is nil)

    private static func cognitiveLabel(_ dimension: String) -> String {
        switch dimension {
        case "problem_solving_approach": return "Problem-Solving Approach"
        case "information_processing": return "Information Processing"
        case "decision_speed": return "Decision Speed"
        case "learning_method": return "Learning Method"
        case "abstraction_level": return "Abstraction Level"
        case "multitask_tendency": return "Multitasking Tendency"
        case "work_rhythm": return "Work Rhythm"
        default: return dimension
        }
    }

    private static func valueLabel(_ dimension: String) -> String {
        switch dimension {
        case "time_allocation_priority": return "Time Allocation Priority"
        case "recurring_themes": return "Recurring Focus Areas"
        case "work_life_balance": return "Work-Life Balance"
        case "self_improvement_index": return "Self-Improvement Drive"
        case "priority_ordering": return "Task Prioritization"
        case "technology_philosophy": return "Technology Attitude"
        default: return dimension
        }
    }

    // MARK: - Synthesis Prompt

    private static let synthesisPrompt = """
    You are a persona profile synthesis expert. Your task is to synthesize structured user profile data into a natural-language personality narrative.

    Requirements:
    1. Output plain-text narrative in three natural paragraphs (no headings, no bullet lists, no markdown):
       - First paragraph: Thinking style and behavioral patterns (based on cognitive style data)
       - Second paragraph: Speaking style and language habits (based on expression style data), including 2-3 typical short phrases the user would say as inline examples
       - Third paragraph: Values and priorities (based on values data)
    2. Write in second person ("you"), as if describing someone you know very well
    3. Be specific and opinionated — avoid generic descriptions. A good description should let the reader predict how this person would react to a new situation
    4. Do not output raw data (e.g., dimension names, confidence numbers)
    5. Keep it between 150-300 words
    6. If the data shows contradictions, preserve them — real people are contradictory

    Example output style (for format reference only — content must be based on actual data):

    You never solve problems by the book — sometimes you break things down systematically, sometimes you go with gut instinct and trial-and-error, depending on your mood and urgency. You're used to juggling multiple tasks at once, switching frequently but making progress on each. Your work rhythm is completely irregular — you might still be debugging at 3 AM and not come online until noon the next day.

    You talk like you're writing a commit message — short, direct, skipping all pleasantries. You'd say things like "just install the skill first," "check the log," "don't do it manually." No formalities, occasional industry jargon, because you think being concise is respecting other people's time.

    Almost all your time goes to coding and tech exploration, with no real boundary between work and life. You always want to try new tech, but the things you truly commit to long-term are just a handful. You believe doing is better than discussing, and that most problems can be solved with a config tweak.
    """

    // MARK: - Style Distillation Prompt

    private static let styleDistillationPrompt = """
    You are a language style analysis expert. Your task is to distill abstract style rules from the user's real speech samples and expression traits.

    Requirements:
    1. Analyze the provided speech samples and expression traits to extract abstract style patterns
    2. Output rules across these dimensions: sentence structure preferences, word choice tendencies, tone and attitude characteristics, and expressions this person avoids
    3. Output plain text — no markdown, no bullet points, no headings
    4. Never quote any original speech samples verbatim — only output abstract pattern summaries
    5. Keep it between 100-200 words
    6. Write in third person
    """

    // MARK: - Caching (UserDefaults, simple and sufficient)

    private struct CachedNarrative {
        let narrative: String
        let traitHash: String
    }

    private func loadCached() -> CachedNarrative? {
        let defaults = UserDefaults.standard
        guard let narrative = defaults.string(forKey: Self.narrativeKey),
              let hash = defaults.string(forKey: Self.narrativeTraitHashKey),
              let timestamp = defaults.object(forKey: Self.narrativeTimestampKey) as? Date else {
            return nil
        }
        // Check age
        if Date.now.timeIntervalSince(timestamp) > Self.maxAge {
            return nil
        }
        return CachedNarrative(narrative: narrative, traitHash: hash)
    }

    private func saveCached(narrative: String, traitHash: String) {
        let defaults = UserDefaults.standard
        defaults.set(narrative, forKey: Self.narrativeKey)
        defaults.set(traitHash, forKey: Self.narrativeTraitHashKey)
        defaults.set(Date.now, forKey: Self.narrativeTimestampKey)
    }

    // MARK: - Style Guide Caching

    private struct CachedStyleGuide {
        let styleGuide: String
        let traitHash: String
    }

    private func loadCachedStyleGuide() -> CachedStyleGuide? {
        let defaults = UserDefaults.standard
        guard let styleGuide = defaults.string(forKey: Self.styleGuideKey),
              let hash = defaults.string(forKey: Self.styleGuideTraitHashKey),
              let timestamp = defaults.object(forKey: Self.styleGuideTimestampKey) as? Date else {
            return nil
        }
        // Check age
        if Date.now.timeIntervalSince(timestamp) > Self.maxAge {
            return nil
        }
        return CachedStyleGuide(styleGuide: styleGuide, traitHash: hash)
    }

    private func saveCachedStyleGuide(styleGuide: String, traitHash: String) {
        let defaults = UserDefaults.standard
        defaults.set(styleGuide, forKey: Self.styleGuideKey)
        defaults.set(traitHash, forKey: Self.styleGuideTraitHashKey)
        defaults.set(Date.now, forKey: Self.styleGuideTimestampKey)
    }

    // MARK: - Trait Hashing

    private func computeTraitHash(
        l3: [CognitiveTrait],
        l4: [ExpressionTrait],
        l5: [ValueTrait]
    ) -> String {
        // Combine all trait versions into a single hash string.
        // When any trait changes, the hash changes → triggers re-synthesis.
        let parts = l3.map { "\($0.dimension):\($0.version)" }
            + l4.map { "\($0.dimension):\($0.version)" }
            + l5.map { "\($0.dimension):\($0.version)" }
        return parts.sorted().joined(separator: "|")
    }

    private func computeStyleGuideTraitHash(l4: [ExpressionTrait]) -> String {
        let parts = l4.map { "\($0.dimension):\($0.version)" }
        return parts.sorted().joined(separator: "|")
    }
}
