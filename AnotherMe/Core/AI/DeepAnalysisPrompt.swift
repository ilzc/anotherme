import Foundation

// MARK: - Supporting Data Structures

struct BehaviorSummary {
    let avgSwitchesPerHour: Double
    let avgSessionMinutes: Double
    let searchReadPracticeRatio: String
    let multiWindowFrequency: Double
    let totalRecords: Int
    let engagementDistribution: [String: Int]
    let avgVisibleAppsCount: Double
    let topIntents: [String]
    let topApps: [(app: String, count: Int)]
    let dominantTopics: [String]
    let sampleActivities: [String]
    let problemSolvingPatterns: [String: Int]
}

struct Layer2TraitSummary {
    let totalTopics: Int
    let newTopicsLast7Days: Int
    let diversityIndex: Double
    let deepTopics: [String]
    let expertTopics: [String]
    let domainDistribution: String
    let learningStyleStats: String
    let topTopicsByTime: String
    let topEdges: String
}

struct ValueSummary {
    let categoryDistribution: [String: Int]
    let persistentTopics: [String]
    let workLifeRatio: Double
    let totalRecords: Int
    let contentSummaries: [String]
    let userIntents: [String]
    let engagementBreakdown: [String: Int]
    let categoryTimeEstimates: [String: Int]
    let learningRecordCount: Int
    let topAppSwitchPatterns: [String]
}

// MARK: - Parsing Models

struct ParsedTrait: Codable {
    let dimension: String
    let value: String
    let confidence: Double
    let description: String?
}

struct TraitsResponse: Codable {
    let traits: [ParsedTrait]
}

// MARK: - Deep Analysis Prompts

enum DeepAnalysisPrompt {

    // MARK: - Layer 1: Behavioral Rhythms

    static func buildLayer1Prompt(summary: Layer1Analyzer.RhythmSummary, language: String = currentResponseLanguage()) -> ChatCompletionRequest {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)

        let systemPrompt = """
        You are a behavioral pattern analysis expert. Based on the user's daily activity rhythm data, analyze their life and work habits.

        Please analyze the following dimensions:
        - chronotype: Sleep-wake type (early_bird/normal/night_owl, with a brief description)
        - focus_pattern: Focus pattern (describe the user's focus characteristics, switching frequency, deep work capability)
        - communication_pattern: Communication pattern (describe how frequently and in what manner the user uses communication tools)
        - weekday_weekend_diff: Weekday vs. weekend difference (describe changes in activity level and focus patterns)

        Return strictly in the following JSON format, do not add any extra text:
        {
          "traits": [
            {"dimension": "chronotype", "value": "descriptive text", "confidence": 0.8}
          ]
        }

        Notes:
        - The value field should be a natural language description (do not just return a label; explain the specific behavioral characteristics)
        - confidence is a float between 0.0-1.0
        - Lower the confidence when data is insufficient
        """ + languageDirective(language)

        let topAppsStr = summary.topApps.prefix(8)
            .map { "\($0.name)(\($0.mins) min)" }
            .joined(separator: ", ")

        let peakHoursStr = summary.peakHours.map { "\($0):00" }.joined(separator: ", ")

        let userMessage = """
        Below are the user's activity rhythm statistics over the past \(summary.dayCount) days:

        - Average daily active duration: \(String(format: "%.1f", summary.avgActiveHours)) hours
        - Average start time: \(summary.avgStartTime)
        - Average end time: \(summary.avgEndTime)
        - Average focus score: \(String(format: "%.2f", summary.avgFocusScore)) (0-1)
        - Average app switches per hour: \(String(format: "%.1f", summary.avgSwitchesPerHour))
        - Peak hours: \(peakHoursStr.isEmpty ? "No data" : peakHoursStr)
        - Frequently used apps: \(topAppsStr.isEmpty ? "No data" : topAppsStr)
        - Work/learning time: \(summary.workMins) min
        - Entertainment/social time: \(summary.leisureMins) min
        - Other time: \(summary.otherMins) min
        - Communication tool ratio: \(String(format: "%.1f%%", summary.commRatio * 100))
        - Communication sessions: \(summary.commSessionCount)
        - Average communication session duration: \(String(format: "%.1f", summary.avgCommSessionMins)) min
        - Weekday average active: \(String(format: "%.0f", summary.avgWeekdayMins)) min, focus score \(String(format: "%.2f", summary.avgWeekdayFocus))
        - Weekend average active: \(String(format: "%.0f", summary.avgWeekendMins)) min, focus score \(String(format: "%.2f", summary.avgWeekendFocus))

        Please analyze this user's behavioral rhythm characteristics.
        """

        return ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: [.text(systemPrompt)]),
                .init(role: "user", content: [.text(userMessage)])
            ],
            temperature: config.temperature,
            responseFormat: .json
        )
    }

    // MARK: - Layer 2: Knowledge & Interests

    static func buildLayer2Prompt(summary: Layer2TraitSummary, language: String = currentResponseLanguage()) -> ChatCompletionRequest {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)

        let systemPrompt = """
        You are a knowledge structure analysis expert. Based on the user's knowledge graph data, analyze their interest and knowledge characteristics.

        Please analyze the following dimensions:
        - knowledge_breadth: Knowledge breadth characteristics (describe the range of coverage and domain diversity)
        - knowledge_depth: Knowledge depth characteristics (describe which domains have been studied in depth)
        - learning_style: Learning style (describe the user's preferred learning paths and methods)
        - interest_evolution: Interest evolution trends (describe recently emerging and persistently followed domains)

        Return strictly in the following JSON format, do not add any extra text:
        {
          "traits": [
            {"dimension": "knowledge_breadth", "value": "descriptive text", "confidence": 0.7}
          ]
        }

        Notes:
        - The value field should be a natural language description
        - confidence is a float between 0.0-1.0
        """ + languageDirective(language)

        let userMessage = """
        Below are the user's knowledge graph statistics:

        - Total topics: \(summary.totalTopics)
        - New topics in the last 7 days: \(summary.newTopicsLast7Days)
        - Domain diversity index: \(String(format: "%.2f", summary.diversityIndex)) (0-1)
        - Deep topics (depthScore >= 0.5): \(summary.deepTopics.isEmpty ? "None" : summary.deepTopics.joined(separator: ", "))
        - Expert topics (depthScore >= 0.8): \(summary.expertTopics.isEmpty ? "None" : summary.expertTopics.joined(separator: ", "))
        - Domain distribution: \(summary.domainDistribution)
        - Learning style statistics: \(summary.learningStyleStats)
        - Most active topics (top 15 by time): \(summary.topTopicsByTime)
        - Strongest associations: \(summary.topEdges)
        """

        return ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: [.text(systemPrompt)]),
                .init(role: "user", content: [.text(userMessage)])
            ],
            temperature: config.temperature,
            responseFormat: .json
        )
    }

    // MARK: - Layer 3: Cognitive Style

    static func buildLayer3Prompt(summary: BehaviorSummary, language: String = currentResponseLanguage()) -> ChatCompletionRequest {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)

        let systemPrompt = """
        You are a behavioral pattern analysis expert. Based on the user's screen behavior data, analyze their cognitive and work style.

        Please analyze the following dimensions:
        - problem_solving_approach: Problem-solving approach (systematic/intuitive/mixed)
        - information_processing: Information processing mode (sequential/parallel/adaptive)
        - decision_speed: Decision speed (quick/moderate/deliberate)
        - learning_method: Learning method (visual/textual/hands_on/community_driven)
        - abstraction_level: Abstract thinking tendency (concrete/balanced/abstract)
        - multitask_tendency: Multitasking tendency (0.0-1.0)
        - work_rhythm: Work rhythm (pomodoro/long_sprint/irregular)

        Return strictly in the following JSON format, do not add any extra text:
        {
          "traits": [
            {"dimension": "problem_solving_approach", "value": "systematic", "confidence": 0.8, "description": "Prefers systematic analysis for problem-solving, accustomed to step-by-step decomposition"},
            {"dimension": "decision_speed", "value": "moderate", "confidence": 0.6, "description": "Moderate decision speed, weighs options based on the situation"}
          ]
        }

        Notes:
        - The value field is an enum value or numeric string, used for programmatic processing
        - The description field is a natural language description, summarizing in one sentence what this trait means for this user
        - confidence is a float between 0.0-1.0, representing analysis certainty
        - Lower the confidence when data is insufficient
        """ + languageDirective(language)

        let engagementStr = summary.engagementDistribution
            .sorted { $0.value > $1.value }
            .map { "\($0.key): \($0.value) times" }
            .joined(separator: ", ")

        let topAppsStr = summary.topApps.prefix(8)
            .map { "\($0.app)(\($0.count) times)" }
            .joined(separator: ", ")

        let topIntentsStr = summary.topIntents
            .joined(separator: "; ")

        let topTopicsStr = summary.dominantTopics.prefix(10)
            .joined(separator: ", ")

        let sampleStr = summary.sampleActivities.prefix(10)
            .enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")

        let patternsStr = summary.problemSolvingPatterns
            .sorted { $0.value > $1.value }
            .map { "\($0.key): \($0.value) times" }
            .joined(separator: ", ")

        let userMessage = """
        Below is the user's behavioral statistics summary (based on \(summary.totalRecords) screen activity records):

        - Average app switches per hour: \(String(format: "%.1f", summary.avgSwitchesPerHour))
        - Average single app session duration: \(String(format: "%.1f", summary.avgSessionMinutes)) min
        - Search/reading/practice ratio: \(summary.searchReadPracticeRatio)
        - Multi-window parallel frequency: \(String(format: "%.2f", summary.multiWindowFrequency))
        - Average simultaneously visible apps: \(String(format: "%.1f", summary.avgVisibleAppsCount))
        - Engagement distribution: \(engagementStr.isEmpty ? "No data" : engagementStr)
        - Frequently used apps: \(topAppsStr.isEmpty ? "No data" : topAppsStr)
        - Common intents: \(topIntentsStr.isEmpty ? "No data" : topIntentsStr)
        - Topics of interest: \(topTopicsStr.isEmpty ? "No data" : topTopicsStr)
        - Problem-solving patterns: \(patternsStr.isEmpty ? "No data" : patternsStr)

        Activity content samples:
        \(sampleStr.isEmpty ? "No data" : sampleStr)

        Please analyze this user's cognitive style.
        """

        return ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: [.text(systemPrompt)]),
                .init(role: "user", content: [.text(userMessage)])
            ],
            temperature: config.temperature,
            responseFormat: .json
        )
    }

    // MARK: - Layer 4: Expression Style

    static func buildLayer4Prompt(samples: [WritingSample], language: String = currentResponseLanguage()) -> ChatCompletionRequest {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)

        let systemPrompt = """
        You are a language style analysis expert. Analyze the following user's writing samples and extract expression characteristics.

        Please analyze the following dimensions:
        - avg_sentence_length: Average sentence length (short/medium/long)
        - formality_score: Formality level (0.0-1.0)
        - humor_index: Humor index (0.0-1.0)
        - emoji_frequency: Emoji usage frequency (none/rare/moderate/frequent)
        - vocabulary_diversity: Vocabulary diversity (0.0-1.0)
        - expression_style: Expression style (concise/detailed/list_oriented)
        - communication_directness: Communication directness (0.0-1.0, 1.0 being very direct)
        - characteristic_words: High-frequency characteristic words (top 10, comma-separated)
        - punctuation_preference: Punctuation preference (e.g., "heavy exclamation mark usage"/"heavy ellipsis usage"/"standard")

        Return strictly in the following JSON format, do not add any extra text:
        {
          "traits": [
            {"dimension": "avg_sentence_length", "value": "medium", "confidence": 0.7},
            {"dimension": "formality_score", "value": "0.6", "confidence": 0.8}
          ]
        }

        Notes:
        - The value field is uniformly of string type
        - confidence is a float between 0.0-1.0
        - Lower the confidence when samples are insufficient
        """ + languageDirective(language)

        let samplesText = samples.prefix(30).enumerated().map { index, sample in
            "[\(index + 1)] Context: \(sample.context), word count: \(sample.wordCount)\n\(sample.content)"
        }.joined(separator: "\n\n")

        let userMessage = """
        Below are the user's \(min(samples.count, 30)) writing samples:

        \(samplesText)

        Please analyze this user's expression style.
        """

        return ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: [.text(systemPrompt)]),
                .init(role: "user", content: [.text(userMessage)])
            ],
            temperature: config.temperature,
            responseFormat: .json
        )
    }

    // MARK: - Layer 4: Style Guide (3-component)

    static func buildStyleGuidePrompt(samples: [WritingSample], language: String = currentResponseLanguage()) -> ChatCompletionRequest {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)

        let systemPrompt = """
        You are a language style analysis expert. Analyze the following user's writing samples and generate a guide for mimicking their speaking style.

        Please return in the following JSON format:
        {
          "style_anchor": "One sentence summarizing this person's communication style essence (no more than 50 words, vivid and evocative)",
          "differentiators": [
            {"trait": "Trait description", "pattern": "Typical expression pattern reflecting this trait"},
            {"trait": "exclusion", "pattern": "Things this person would never do"}
          ],
          "selected_examples": [
            {"context": "Scenario", "text": "Original text", "note": "Reason for selection"}
          ]
        }

        Requirements:
        - style_anchor: Concise and powerful, e.g., "A straightforward engineer who habitually uses the fewest words to make things clear"
        - differentiators: 3-5 most prominent traits; the last one must be an exclusion (what this person would never express)
        - selected_examples: Curate 15-25 original texts from the samples that best represent this person's style
          - Selection criteria: Diversity (covering different scenarios), representativeness (typical expressions), uniqueness (distinct from generic expressions)
          - Deduplication: Keep only one when expressions are similar
          - Preserve the complete original text, do not truncate
          - note: Brief explanation of selection reason (within 10 words)
        """ + languageDirective(language)

        let samplesText = samples.enumerated().map { index, sample in
            "[\(index + 1)] (\(sample.context)) \(sample.content)"
        }.joined(separator: "\n")

        let userMessage = """
        Below are the user's \(samples.count) writing samples:

        \(samplesText)

        Please generate a style guide for this user's expression style.
        """

        return ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: [.text(systemPrompt)]),
                .init(role: "user", content: [.text(userMessage)])
            ],
            temperature: config.temperature,
            responseFormat: .json
        )
    }

    /// Parse the style guide response into 3 trait entries.
    static func parseStyleGuideResponse(_ response: ChatCompletionResponse) throws -> (anchor: String, differentiators: String, examples: String) {
        guard let content = response.choices.first?.message.content else {
            throw AIClientError.emptyResponse
        }
        guard let data = content.data(using: .utf8) else {
            throw AIClientError.invalidResponse
        }

        // Parse as generic JSON to extract three parts
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIClientError.invalidResponse
        }

        let anchor = json["style_anchor"] as? String ?? ""

        // Re-serialize differentiators and examples as JSON strings for storage
        let diffsData = try JSONSerialization.data(
            withJSONObject: json["differentiators"] ?? [],
            options: [.sortedKeys]
        )
        let diffsStr = String(data: diffsData, encoding: .utf8) ?? "[]"

        let examplesData = try JSONSerialization.data(
            withJSONObject: json["selected_examples"] ?? [],
            options: [.sortedKeys]
        )
        let examplesStr = String(data: examplesData, encoding: .utf8) ?? "[]"

        return (anchor, diffsStr, examplesStr)
    }

    // MARK: - Layer 5: Values & Priorities

    static func buildLayer5Prompt(summary: ValueSummary, language: String = currentResponseLanguage()) -> ChatCompletionRequest {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)

        let systemPrompt = """
        You are a behavioral psychology analysis expert. Based on the user's long-term behavioral data, infer their deep values and priorities.

        Please analyze the following dimensions:
        - time_allocation_priority: Time allocation priority (list the top 3, e.g., "coding,learning,communication")
        - recurring_themes: Recurring themes (list the top 5 keywords, comma-separated)
        - work_life_balance: Work-life balance (0.0-1.0, 0.5 means balanced)
        - self_improvement_index: Self-improvement index (0.0-1.0)
        - priority_ordering: Which type of task is prioritized when multitasking (based on switching pattern analysis)
        - technology_philosophy: Technology philosophy tendency (early_adopter/pragmatist/conservative)

        Return strictly in the following JSON format, do not add any extra text:
        {
          "traits": [
            {"dimension": "time_allocation_priority", "value": "coding,learning,communication", "confidence": 0.7, "description": "Time is primarily invested in coding, followed by learning and communication"},
            {"dimension": "work_life_balance", "value": "0.3", "confidence": 0.6, "description": "Work dominates, with relatively little personal time"}
          ]
        }

        Notes:
        - The value field is an enum value, number, or comma-separated list, used for programmatic processing
        - The description field is a natural language description, summarizing in one sentence what this trait means for this user
        - confidence is a float between 0.0-1.0
        - Lower the confidence when data is insufficient
        """ + languageDirective(language)

        let categoryDistStr = summary.categoryDistribution
            .sorted { $0.value > $1.value }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")

        let topicsStr = summary.persistentTopics.joined(separator: ", ")

        let categoryTimeStr = summary.categoryTimeEstimates
            .sorted { $0.value > $1.value }
            .map { "\($0.key): \($0.value) min" }
            .joined(separator: ", ")

        let engagementStr = summary.engagementBreakdown
            .sorted { $0.value > $1.value }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")

        let switchStr = summary.topAppSwitchPatterns
            .prefix(10)
            .joined(separator: ", ")

        let contentSummariesStr = summary.contentSummaries
            .prefix(20)
            .enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")

        let userIntentsStr = summary.userIntents
            .prefix(15)
            .enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")

        let userMessage = """
        Below are the user's long-term behavioral statistics (based on \(summary.totalRecords) records):

        - Activity category distribution: \(categoryDistStr)
        - Estimated time per category: \(categoryTimeStr.isEmpty ? "No data" : categoryTimeStr)
        - Persistently followed topics: \(topicsStr.isEmpty ? "No data" : topicsStr)
        - Work/life time ratio: \(String(format: "%.2f", summary.workLifeRatio))
        - Engagement distribution: \(engagementStr.isEmpty ? "No data" : engagementStr)
        - Learning-related record count: \(summary.learningRecordCount)
        - App switching patterns (top 10 by frequency): \(switchStr.isEmpty ? "No data" : switchStr)

        User's activity content summaries (sampled):
        \(contentSummariesStr.isEmpty ? "No data" : contentSummariesStr)

        User's intent inferences (sampled):
        \(userIntentsStr.isEmpty ? "No data" : userIntentsStr)

        Please infer this user's deep values.
        """

        return ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: [.text(systemPrompt)]),
                .init(role: "user", content: [.text(userMessage)])
            ],
            temperature: config.temperature,
            responseFormat: .json
        )
    }

    // MARK: - Snapshot Summary

    static func buildSnapshotSummaryPrompt(traitsJSON: String, language: String = currentResponseLanguage()) -> ChatCompletionRequest {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)

        let systemPrompt = """
        You are a personality profile generation expert. Based on the user's multi-dimensional trait data, generate a concise second-person description.

        Requirements:
        - Use second person ("you")
        - Keep it within 200 words
        - Only describe traits with confidence > 0.5
        - Use a warm, objective tone; avoid absolutist statements
        - Return the description text directly, do not wrap it in JSON
        """ + languageDirective(language)

        let userMessage = """
        Below is the user's multi-dimensional trait data (JSON format):

        \(traitsJSON)

        Please generate a personality profile description.
        """

        return ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: [.text(systemPrompt)]),
                .init(role: "user", content: [.text(userMessage)])
            ],
            temperature: config.temperature,
            responseFormat: nil
        )
    }

    // MARK: - MBTI Analysis

    /// Input summary for MBTI analysis, combining all layer traits + L2 ground-truth.
    struct MBTISummary {
        let traitsJSON: String            // All 5-layer traits serialized
        let l2DomainDistribution: String  // e.g. "work: 275, social: 101, ..."
        let l2DepthDistribution: String   // e.g. "shallow: 380, moderate: 10, deep: 2, expert: 0"
        let l2TopTopics: String           // Top 15 topics with depth scores
    }

    /// AI response model for MBTI analysis.
    struct MBTIResponse: Codable {
        let type: String
        let dimensions: MBTIDimensions
        let summary: String

        struct MBTIDimensions: Codable {
            let EI: MBTIDimension
            let SN: MBTIDimension
            let TF: MBTIDimension
            let JP: MBTIDimension
        }

        struct MBTIDimension: Codable {
            let result: String
            let strength: String
            let confidence: Double
            let evidence: [String]
        }
    }

    static func buildMBTIPrompt(summary: MBTISummary, language: String = currentResponseLanguage()) -> ChatCompletionRequest {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)

        let systemPrompt = """
        You are an MBTI personality analysis expert. Based on the following user behavioral data (from a 5-layer personality model analysis), infer the user's most likely MBTI type.

        ## Analysis Requirements
        Analyze each of the four MBTI dimensions one by one. For each dimension:
        1. List specific evidence supporting the tendency (cite specific content from the input data)
        2. Provide the tendency strength (strong/moderate/weak)
        3. Provide the confidence for that dimension (0.0-1.0)

        ## Dimension Mapping Guide
        - E/I (Extraversion/Introversion): Focus on Layer1 communication patterns, Layer4 expression style (directness, expressiveness, emoji usage), Layer2 knowledge domains (proportion of social topics)
        - S/N (Sensing/Intuition): Focus on Layer3 abstract thinking level, Layer3 information processing mode, Layer2 knowledge breadth vs. depth, concrete vs. abstract topic distribution
        - T/F (Thinking/Feeling): Focus on Layer3 decision-making approach, Layer4 formality/emotional expression, Layer5 value judgments and technology philosophy
        - J/P (Judging/Perceiving): Focus on Layer1 work rhythm and regularity, Layer3 multitasking tendency, Layer5 time allocation and priorities

        ## Known Bias Notes
        - All data comes from screen behavior observation; E/I judgment has a natural introversion bias (everyone appears more I when in front of a computer)
        - J/P dimension has the strongest signal (behavioral regularity is directly observable)
        - T/F dimension has weaker signal (internal decision-making processes are hard to infer from screen behavior)
        - S/N dimension has the most indirect signal (cognitive style must be inferred indirectly from behavioral patterns)
        - If evidence for a dimension is insufficient, lower the confidence and explain in the evidence

        ## Output Format (strict JSON, do not add any extra text)
        {
          "type": "INTJ",
          "dimensions": {
            "EI": {"result": "I", "strength": "strong", "confidence": 0.75, "evidence": ["Evidence 1...", "Evidence 2..."]},
            "SN": {"result": "N", "strength": "moderate", "confidence": 0.6, "evidence": ["Evidence 1...", "Evidence 2..."]},
            "TF": {"result": "T", "strength": "moderate", "confidence": 0.55, "evidence": ["Evidence 1...", "Evidence 2..."]},
            "JP": {"result": "J", "strength": "strong", "confidence": 0.8, "evidence": ["Evidence 1...", "Evidence 2..."]}
          },
          "summary": "Overall personality description combining the user's actual data (100-200 words)"
        }

        Notes:
        - type must be a 4-letter MBTI type (e.g., INTJ, ENFP, etc.)
        - result can only be one of the two letters for the corresponding dimension
        - strength can only be "strong"/"moderate"/"weak"
        - evidence: at least 2 items per dimension, citing specific data
        - When uncertain, prefer lowering confidence rather than forcing a judgment
        """ + languageDirective(language)

        let userMessage = """
        Below is the user's multi-dimensional personality trait data:

        \(summary.traitsJSON)

        ## Supplementary Data (Knowledge Graph ground-truth statistics)

        Domain distribution: \(summary.l2DomainDistribution)
        Depth distribution: \(summary.l2DepthDistribution)
        Hot topics (top 15 by time): \(summary.l2TopTopics)

        Please infer this user's MBTI type based on all the above data.
        """

        return ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: [.text(systemPrompt)]),
                .init(role: "user", content: [.text(userMessage)])
            ],
            temperature: config.temperature,
            responseFormat: .json
        )
    }

    static func parseMBTIResponse(_ response: ChatCompletionResponse) throws -> MBTIResponse {
        guard let content = response.choices.first?.message.content else {
            throw AIClientError.emptyResponse
        }
        guard let data = content.data(using: .utf8) else {
            throw AIClientError.invalidResponse
        }
        return try JSONDecoder().decode(MBTIResponse.self, from: data)
    }

    // MARK: - Big Five (OCEAN) Analysis

    /// Input summary for Big Five analysis.
    struct BigFiveSummary {
        let traitsJSON: String
        let rhythmStability: String
        let knowledgeDiversityIndex: String
        let socialCategoryRatio: String
        let l2DomainDistribution: String
        let l2DepthDistribution: String
        let l2TopTopics: String
    }

    /// AI response model for Big Five analysis.
    struct BigFiveResponse: Codable {
        let openness: DimensionScore
        let conscientiousness: DimensionScore
        let extraversion: DimensionScore
        let agreeableness: DimensionScore
        let neuroticism: DimensionScore
        let summary: String

        struct DimensionScore: Codable {
            let score: Double
            let strength: String
            let confidence: Double
            let evidence: [String]
        }
    }

    static func buildBigFivePrompt(summary: BigFiveSummary, language: String = currentResponseLanguage()) -> ChatCompletionRequest {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.deepAnalysis)

        let systemPrompt = """
        You are a Big Five (OCEAN) personality analysis expert. Based on the following user's screen behavior observation data (from a 5-layer personality model analysis), infer the user's scores on the 5 Big Five personality dimensions.

        ## Scoring Rules
        - Give a continuous score of 0.0-1.0 for each dimension (0.5 is neutral/population average)
        - Provide a strength label: >=0.7 or <=0.3 is "strong", >0.3 and <0.45 or >0.55 and <0.7 is "moderate", >=0.45 and <=0.55 is "weak"
        - Provide the confidence for that dimension (0.0-1.0)
        - List 3-5 specific pieces of evidence (citing content from the input data)

        ## Dimension Mapping Guide

        ### Openness 0=conservative and practical, 1=innovative and curious
        Primary data: Layer2 knowledge breadth + new topic exploration frequency, Layer3 abstract thinking tendency, Layer5 learning index
        Secondary data: Layer4 vocabulary diversity
        Supplementary statistics: Knowledge domain diversity index, depth distribution

        ### Conscientiousness 0=casual and flexible, 1=rigorous and self-disciplined
        Primary data: Layer1 schedule regularity + focus level + switching frequency, Layer3 systematization level + multitasking tendency
        Secondary data: Layer5 priority clarity
        Supplementary statistics: Rhythm stability (focusScore standard deviation)

        ### Extraversion 0=reserved and solitary, 1=outgoing and social
        Primary data: Layer1 social tool usage + Layer4 expression directness + emoji frequency
        Secondary data: Layer2 social topic proportion, Layer4 expression style
        Supplementary statistics: Social app time proportion

        ### Agreeableness 0=competitive and questioning, 1=cooperative and trusting
        Primary data: Layer4 expression formality + humor + style warmth
        Secondary data: Layer5 technology philosophy tendency, Layer4 characteristic words
        Note: This dimension has the weakest signal; confidence should be lower

        ### Neuroticism 0=emotionally stable, 1=emotionally sensitive
        Primary data: Layer1 focus volatility + schedule consistency, Layer5 work-life balance extremity
        Secondary data: Layer4 punctuation preferences (exclamation marks, etc.), Layer3 decision consistency
        Supplementary statistics: Rhythm stability

        ## Known Data Biases (must be considered)
        1. **E dimension systematically low**: All data comes from screen behavior; offline socializing is completely invisible. If social signals are insufficient, move the E score toward 0.5 rather than defaulting to a low score.
        2. **C dimension may be inflated**: Programmers/knowledge workers using an IDE for long periods without switching does not indicate high self-discipline; it may just be the nature of their work. Combine with schedule regularity for a comprehensive judgment.
        3. **A dimension has the weakest signal**: Screen behavior can hardly directly observe interpersonal collaboration attitudes. Honestly lower A's confidence (recommended not to exceed 0.6).
        4. **N dimension requires time span**: A single extreme value does not indicate high N; look for stable patterns across multiple days/weeks.
        5. **Overall bias**: Data only reflects digital behavior, not the complete personality. Maintain caution for all dimensions; lower confidence when evidence is insufficient.

        ## Output Format (strict JSON, do not add any extra text)
        {
          "openness": {"score": 0.72, "strength": "strong", "confidence": 0.75, "evidence": ["Evidence 1", "Evidence 2", "Evidence 3"]},
          "conscientiousness": {"score": 0.55, "strength": "weak", "confidence": 0.80, "evidence": ["Evidence 1", "Evidence 2", "Evidence 3"]},
          "extraversion": {"score": 0.35, "strength": "moderate", "confidence": 0.55, "evidence": ["Evidence 1", "Evidence 2", "Evidence 3"]},
          "agreeableness": {"score": 0.60, "strength": "moderate", "confidence": 0.45, "evidence": ["Evidence 1", "Evidence 2"]},
          "neuroticism": {"score": 0.28, "strength": "strong", "confidence": 0.60, "evidence": ["Evidence 1", "Evidence 2", "Evidence 3"]},
          "summary": "Comprehensive personality description combining the user's actual data (100-200 words)"
        }

        Notes:
        - score must be between 0.0-1.0
        - strength can only be "strong"/"moderate"/"weak"
        - evidence: at least 2 items per dimension, citing specific data
        - When uncertain, prefer lowering confidence rather than forcing a judgment
        """ + languageDirective(language)

        let userMessage = """
        Below is the user's multi-dimensional personality trait data:

        \(summary.traitsJSON)

        ## Supplementary Statistical Data

        Rhythm stability (focusScore standard deviation, lower means more stable): \(summary.rhythmStability)
        Knowledge diversity index (domains/nodes): \(summary.knowledgeDiversityIndex)
        Social topic proportion: \(summary.socialCategoryRatio)
        Knowledge graph domain distribution: \(summary.l2DomainDistribution)
        Knowledge graph depth distribution: \(summary.l2DepthDistribution)
        Hot topics (Top 15): \(summary.l2TopTopics)

        Please infer this user's Big Five personality traits based on all the above data.
        """

        return ChatCompletionRequest(
            model: config.modelName,
            messages: [
                .init(role: "system", content: [.text(systemPrompt)]),
                .init(role: "user", content: [.text(userMessage)])
            ],
            temperature: config.temperature,
            responseFormat: .json
        )
    }

    static func parseBigFiveResponse(_ response: ChatCompletionResponse) throws -> BigFiveResponse {
        guard let content = response.choices.first?.message.content else {
            throw AIClientError.emptyResponse
        }
        guard let data = content.data(using: .utf8) else {
            throw AIClientError.invalidResponse
        }
        return try JSONDecoder().decode(BigFiveResponse.self, from: data)
    }

    // MARK: - Response Parsing

    static func parseTraitsResponse(_ response: ChatCompletionResponse) throws -> [ParsedTrait] {
        guard let content = response.choices.first?.message.content else {
            throw AIClientError.emptyResponse
        }

        guard let data = content.data(using: .utf8) else {
            throw AIClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(TraitsResponse.self, from: data)
        return decoded.traits
    }
}
