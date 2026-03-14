import SwiftUI

struct TraitCardView: View {
    let title: String
    let icon: String
    let color: Color
    let traits: [TraitDisplay]
    let layer: Int

    @State private var isExpanded = true

    struct TraitDisplay {
        let dimension: String
        let value: String
        let confidence: Double
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if traits.isEmpty {
                    HStack {
                        Image(systemName: "hourglass")
                            .foregroundStyle(.secondary)
                        Text("Collecting data...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let visibleTraits = isExpanded
                        ? traits
                        : Array(traits.prefix(3))
                    ForEach(visibleTraits, id: \.dimension) { trait in
                        traitRow(trait)
                    }

                    if traits.count > 3 {
                        Button(isExpanded ? "Collapse" : "Expand all (\(traits.count))") {
                            withAnimation { isExpanded.toggle() }
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                if !traits.isEmpty {
                    let avgConf = traits.map(\.confidence).reduce(0, +) / Double(traits.count)
                    Text("Confidence \(Int(avgConf * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func traitRow(_ trait: TraitDisplay) -> some View {
        let numericValue = parseNumericValue(trait.value)

        if let num = numericValue {
            // Numeric trait: show progress bar for the value
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formatDimension(trait.dimension))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(trait.value)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(color)
                    Text("(Confidence: \(Int(trait.confidence * 100))%)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.12))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(0.55))
                            .frame(width: geo.size.width * min(1.0, max(0, num)))
                    }
                }
                .frame(height: 4)
            }
        } else {
            // Text trait: no progress bar, just label + value + confidence
            HStack(alignment: .firstTextBaseline) {
                Text(formatDimension(trait.dimension))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("(Confidence: \(Int(trait.confidence * 100))%)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(formatValue(trait.value))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Helpers

    /// Try to parse value as a 0-1 numeric score.
    private func parseNumericValue(_ value: String) -> Double? {
        guard let num = Double(value) else { return nil }
        // Only treat as numeric bar if it looks like a 0-1 score
        return (num >= 0 && num <= 1.0) ? num : nil
    }

    /// Maps dimension keys to English display names.
    private func formatDimension(_ dim: String) -> String {
        let map: [String: String] = [
            // Layer 1: Behavioral Rhythms
            "chronotype": "Chronotype",
            "focus_pattern": "Focus Pattern",
            "app_preferences": "App Preferences",
            "work_rhythm": "Work Rhythm",
            "communication_pattern": "Communication Pattern",
            "weekday_weekend_diff": "Weekday/Weekend Diff",
            // Layer 2: Knowledge Graph
            "breadth": "Knowledge Breadth",
            "depth_distribution": "Depth Distribution",
            "knowledge_domains": "Knowledge Domains",
            "knowledge_breadth": "Knowledge Breadth",
            "knowledge_depth": "Knowledge Depth",
            "learning_style": "Learning Style",
            "interest_evolution": "Interest Evolution",
            // Layer 3: Cognitive Style
            "problem_solving_approach": "Problem Solving",
            "information_processing": "Info Processing",
            "decision_speed": "Decision Speed",
            "learning_method": "Learning Method",
            "abstraction_level": "Abstract Thinking",
            "multitask_tendency": "Multitasking",
            // Layer 4: Expression Style
            "avg_sentence_length": "Avg Sentence Length",
            "formality_score": "Formality",
            "humor_index": "Humor Index",
            "emoji_frequency": "Emoji Usage",
            "vocabulary_diversity": "Vocabulary Diversity",
            "expression_style": "Expression Style",
            "communication_directness": "Directness",
            "characteristic_words": "Characteristic Words",
            "punctuation_preference": "Punctuation Preference",
            "style_anchor": "Style Anchor",
            "key_differentiators": "Key Differentiators",
            "curated_examples": "Representative Examples",
            // Layer 5: Values & Priorities
            "time_allocation_priority": "Time Allocation Priority",
            "recurring_themes": "Recurring Themes",
            "work_life_balance": "Work-Life Balance",
            "self_improvement_index": "Self-Improvement",
            "priority_ordering": "Priority Ordering",
            "technology_philosophy": "Tech Philosophy",
        ]
        return map[dim] ?? dim
    }

    /// Attempts to parse a JSON string into a readable display value.
    private func formatValue(_ jsonStr: String) -> String {
        // Try JSON object
        if let data = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let type = dict["type"] as? String { return type }
            if dict.count == 1, let val = dict.values.first { return "\(val)" }
            return dict.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        }
        // Try JSON array — show count for large arrays
        if let data = jsonStr.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            if arr.count > 3 {
                return "\(arr.count) records"
            }
        }
        // Truncate long strings
        if jsonStr.count > 80 {
            return String(jsonStr.prefix(77)) + "..."
        }
        return jsonStr
    }
}
