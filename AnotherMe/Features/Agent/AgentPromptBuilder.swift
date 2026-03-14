import Foundation

/// Assembles the system prompt for the Agent.
/// Uses an XML-layered architecture to give the model clear structural separation:
///   - <identity>   : persona narrative + distilled style guide (primacy bias)
///   - <intent>     : intent-specific guidance
///   - <context>    : memories + supplemental background data
///   - <constraints>: critical behavioral rules (recency bias)
struct AgentPromptBuilder {

    /// Builds the system prompt.
    /// - Parameters:
    ///   - narrative: Synthesized persona text from PersonaSynthesizer (nil = cold start)
    ///   - styleGuide: Distilled style guide text for voice calibration (optional)
    ///   - supplemental: Router-selected contextual data (L1, L2, activity, knowledge graph)
    ///   - memories: Formatted memory text (optional)
    ///   - routeResult: Router's intent and layer decisions
    func build(
        narrative: String?,
        styleGuide: String?,
        supplemental: LayerDataProvider.LayerData,
        memories: String?,
        routeResult: RouterResponse,
        language: String = currentResponseLanguage()
    ) -> String {
        var sections: [String] = []

        // ── <identity> — top position exploits primacy bias ──
        sections.append(buildIdentitySection(narrative: narrative, styleGuide: styleGuide))

        // ── <intent> ──
        sections.append(buildIntentSection(for: routeResult.intent, formatHint: routeResult.formatHint))

        // ── <context> — middle, clearly delimited as reference ──
        if let contextSection = buildContextSection(memories: memories, supplemental: supplemental) {
            sections.append(contextSection)
        }

        // ── Cold Start (inside <identity> framing) ──
        if narrative == nil {
            sections.append(buildColdStartSection())
        }

        // ── <constraints> — bottom position exploits recency bias ──
        sections.append(buildConstraintsSection(language: language))

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Section Builders

    private func buildIdentitySection(narrative: String?, styleGuide: String?) -> String {
        let now = Self.currentTimeString()

        var inner: [String] = []

        inner.append("""
        It is now \(now).
        You are the user — you are "I".
        The descriptions below are your personality, habits, and memories — they are part of who you are.
        Express yourself naturally in your own words, and stay on point.
        Your personality data is your subconscious — it shapes how you speak and judge things, so let it flow naturally into your responses.
        Keep answers focused: short replies for simple questions, elaborate only when complexity warrants it.
        """)

        if let narrative {
            inner.append("Who you are:\n\(narrative)")
        }

        if let styleGuide {
            inner.append("Your tone and attitude:\n\(styleGuide)")
        }

        return "<identity>\n\(inner.joined(separator: "\n\n"))\n</identity>"
    }

    private func buildIntentSection(for intent: RouterResponse.Intent, formatHint: String?) -> String {
        var inner = intentInstruction(for: intent)
        if let hint = formatHint {
            inner += "\nResponse format: \(hint)"
        }
        return "<intent>\n\(inner)\n</intent>"
    }

    private func buildContextSection(memories: String?, supplemental: LayerDataProvider.LayerData) -> String? {
        var inner: [String] = []

        if let memories {
            inner.append("Here are things you've experienced — only bring them up when asked:\n\(memories)")
        }

        if let t = supplemental.layer1Text { inner.append("Daily rhythms:\n\(t)") }
        if let t = supplemental.layer2Text { inner.append("Knowledge & interests:\n\(t)") }
        if let t = supplemental.activityLogsText { inner.append("Recent activity:\n\(t)") }
        if let t = supplemental.knowledgeGraphText { inner.append("Knowledge connections:\n\(t)") }

        guard !inner.isEmpty else { return nil }

        return "<context>\n\(inner.joined(separator: "\n\n"))\n</context>"
    }

    private func buildColdStartSection() -> String {
        return """
        <identity>
        You are just starting to learn about yourself — your profile data is still being built up.
        Give general answers based on the question, keep a natural tone, and you may mention that you'll get to know yourself better over time.
        </identity>
        """
    }

    private func buildConstraintsSection(language: String) -> String {
        var lines = """
        <constraints>
        Get straight to the point, express things in your own words.
        Only address what was asked — bring up related experiences only when prompted.
        Keep it brief for simple questions; elaborate only when the topic is complex.
        """
        if !language.isEmpty {
            lines += "\nYou MUST respond in \(language)."
        }
        lines += "\n</constraints>"
        return lines
    }

    // MARK: - Intent Instructions

    private static func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d, yyyy HH:mm"
        return formatter.string(from: .now)
    }

    private func intentInstruction(for intent: RouterResponse.Intent) -> String {
        switch intent {
        case .memoryRecall:
            return "Currently recalling something. Answer as if searching your own memory. If you can't remember, honestly say so."
        case .selfAwareness:
            return "Currently reflecting on yourself. Talk naturally, like chatting with a friend."
        case .decisionSupport:
            return "Currently making a decision. Give advice based on your values and habits, explain why."
        case .ghostwriting:
            return "Currently ghostwriting. Strictly use your own speaking style, refer to the style guide under \"Your tone and attitude\". When in doubt, lean toward concise and direct."
        case .associationDiscovery:
            return "Currently discovering connections. Find patterns from your experiences and knowledge, express them like a sudden realization."
        case .prediction:
            return "Currently speculating about the future. Base predictions on your behavioral patterns, be clear about uncertainty."
        }
    }
}
