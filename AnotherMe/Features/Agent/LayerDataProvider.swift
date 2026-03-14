import Foundation

/// Queries layer databases and formats data as text for injection into agent prompts.
struct LayerDataProvider {
    let activityStore: ActivityStore
    let layer1Store: Layer1Store
    let layer2Store: Layer2Store
    let layer3Store: Layer3Store
    let layer4Store: Layer4Store
    let layer5Store: Layer5Store

    struct LayerData {
        var layer1Text: String?
        var layer2Text: String?
        var layer3Text: String?
        var layer4Text: String?
        var layer5Text: String?
        var activityLogsText: String?
        var knowledgeGraphText: String?
        var memoriesText: String?
    }

    /// Fetches layer data asynchronously, running all DB queries off the main thread.
    func fetchData(for route: RouterResponse) async throws -> LayerData {
        try await Task.detached {
            try self.fetchDataSync(for: route)
        }.value
    }

    /// Fetches a few formatted L4 style examples for voice calibration in the prompt.
    func fetchStyleExamples() async throws -> String? {
        try await Task.detached {
            let traits = try self.layer4Store.fetchTraits()
            let samples = try self.layer4Store.fetchRecentSamples(limit: 8)
            let text = self.formatStyleExamples(traits: traits, samples: samples)
            return text.isEmpty ? nil : text
        }.value
    }

    /// Synchronous implementation – always called from a background context.
    /// Fetches supplemental layers (L1, L2, activity logs, knowledge graph) based on routing.
    private func fetchDataSync(for route: RouterResponse) throws -> LayerData {
        var data = LayerData()
        let timeRange = parseTimeRange(route.timeRange)

        for layer in route.layersNeeded {
            switch layer {
            case 1:
                let traits = try layer1Store.fetchTraits()
                let rhythms = try layer1Store.fetchRecentRhythms(limit: 7)
                data.layer1Text = formatLayer1(traits: traits, rhythms: rhythms)
            case 2:
                let traits = try layer2Store.fetchTraits()
                data.layer2Text = formatLayer2(traits: traits)
            case 3, 4, 5:
                break // Core persona layers are fetched separately via fetchCorePersona()
            default:
                break
            }
        }

        if route.needActivityLogs {
            let records = try activityStore.fetch(from: timeRange.start, to: timeRange.end)
            data.activityLogsText = formatActivityLogs(Array(records.suffix(50)))
        }

        if route.needKnowledgeGraph {
            let nodes = try layer2Store.fetchTopNodes(limit: 20)
            let edges = try layer2Store.fetchStrongestEdges(limit: 30)
            data.knowledgeGraphText = formatKnowledgeGraph(nodes: nodes, edges: edges)
        }

        return data
    }

    // MARK: - Time Range Parsing

    private func parseTimeRange(_ range: String) -> (start: Date, end: Date) {
        let now = Date.now
        let calendar = Calendar.current

        switch range {
        case "today":
            let startOfDay = calendar.startOfDay(for: now)
            return (startOfDay, now)
        case "last_7_days":
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case "last_30_days":
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (start, now)
        case "all":
            let distantPast = calendar.date(byAdding: .year, value: -10, to: now) ?? now
            return (distantPast, now)
        default:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        }
    }

    // MARK: - Layer 1: Behavioral Rhythms

    private func formatLayer1(traits: [RhythmTrait], rhythms: [DailyRhythm]) -> String {
        var lines: [String] = []

        for trait in traits {
            lines.append("- \(trait.dimension): \(trait.value) (Confidence \(String(format: "%.0f%%", trait.confidence * 100)))")
        }

        if !rhythms.isEmpty {
            let totalMins = rhythms.map(\.totalActiveMins).reduce(0, +)
            let avgMins = rhythms.isEmpty ? 0 : totalMins / rhythms.count
            let avgHours = String(format: "%.1f", Double(avgMins) / 60.0)
            lines.append("- Avg active time (last \(rhythms.count) days): \(avgHours) hr")

            let avgFocus = rhythms.map(\.focusScore).reduce(0, +) / Double(rhythms.count)
            lines.append("- Avg focus score (last \(rhythms.count) days): \(String(format: "%.2f", avgFocus))")

            if let latest = rhythms.first {
                if let start = latest.activeStart {
                    lines.append("- Recent active start: \(start)")
                }
                if let end = latest.activeEnd {
                    lines.append("- Recent active end: \(end)")
                }
                if !latest.peakHours.isEmpty {
                    let peakStr = latest.peakHours.map { "\($0):00" }.joined(separator: ", ")
                    lines.append("- Recent peak hours: \(peakStr)")
                }
            }
        }

        return lines.isEmpty ? "No behavioral rhythm data" : lines.joined(separator: "\n")
    }

    // MARK: - Layer 2: Knowledge & Interests

    private func formatLayer2(traits: [KnowledgeTrait]) -> String {
        var lines: [String] = []

        for trait in traits {
            lines.append("- \(trait.dimension): \(trait.value) (Confidence \(String(format: "%.0f%%", trait.confidence * 100)))")
        }

        return lines.isEmpty ? "No knowledge & interest data" : lines.joined(separator: "\n")
    }

    // MARK: - Layer 3: Cognitive Style

    private func formatLayer3(traits: [CognitiveTrait]) -> String {
        let lines = traits
            .filter { $0.confidence >= 0.5 }
            .compactMap { $0.description ?? Self.fallbackDescribe($0.dimension, value: $0.value) }
            .map { "- \($0)" }

        return lines.isEmpty ? "No cognitive style data" : lines.joined(separator: "\n")
    }

    /// Fallback for old data without description. Will be phased out as re-analysis populates descriptions.
    private static func fallbackDescribe(_ dimension: String, value: String) -> String {
        "\(dimension): \(value)"
    }

    // MARK: - Layer 4: Expression & Communication

    private static let contextNameMap: [String: String] = [
        "browser": "while browsing", "work_chat": "in work chat",
        "code_comment": "in code comments", "social_media": "on social media",
        "email": "writing email", "document": "writing docs", "chat": "in casual chat",
    ]

    private func formatLayer4(traits: [ExpressionTrait], samples: [WritingSample]) -> String {
        // Try style guide format first (richer, more useful for mimicry)
        let anchor = traits.first(where: { $0.dimension == "style_anchor" })?.value
        let diffsJSON = traits.first(where: { $0.dimension == "key_differentiators" })?.value
        let examplesJSON = traits.first(where: { $0.dimension == "curated_examples" })?.value

        if let anchor, !anchor.isEmpty {
            var lines: [String] = []
            lines.append("Speaking style: \(anchor)")

            if let diffsJSON,
               let diffsData = diffsJSON.data(using: .utf8),
               let diffs = try? JSONSerialization.jsonObject(with: diffsData) as? [[String: String]] {
                lines.append("\nLanguage habits:")
                for diff in diffs {
                    let trait = diff["trait"] ?? ""
                    let pattern = diff["pattern"] ?? ""
                    lines.append("- \(trait): \(pattern)")
                }
            }

            if let examplesJSON,
               let exData = examplesJSON.data(using: .utf8),
               let examples = try? JSONSerialization.jsonObject(with: exData) as? [[String: String]] {
                // Pick up to 10 short, diverse examples
                let selected = examples.prefix(10)
                lines.append("\nThings you've said in various contexts (each is an independent quote showing your style):")
                for (i, ex) in selected.enumerated() {
                    let rawCtx = ex["context"] ?? ""
                    let ctx = Self.contextNameMap[rawCtx] ?? rawCtx
                    let text = ex["text"] ?? ""
                    let truncated = text.count > 60 ? String(text.prefix(60)) + "…" : text
                    lines.append("\(i + 1). \(ctx)「\(truncated)」")
                }
            }

            return lines.joined(separator: "\n")
        }

        // Fallback: use basic trait format if style guide not yet generated
        var lines: [String] = []
        for trait in traits where trait.confidence >= 0.5 {
            lines.append("- \(trait.dimension): \(trait.value)")
        }

        if !samples.isEmpty {
            lines.append("\nThings you've said (each independent):")
            for (i, sample) in samples.prefix(8).enumerated() {
                let preview = String(sample.content.prefix(80))
                let ctx = Self.contextNameMap[sample.context] ?? sample.context
                lines.append("\(i + 1). \(ctx)「\(preview)」")
            }
        }

        return lines.isEmpty ? "No expression style data" : lines.joined(separator: "\n")
    }

    // MARK: - Style Examples (for prompt voice calibration)

    /// Formats a small set of real user quotes as few-shot style examples.
    /// This is separate from the full L4 formatting — only used in the chat prompt.
    private func formatStyleExamples(traits: [ExpressionTrait], samples: [WritingSample]) -> String {
        var lines: [String] = []

        // Try curated examples from style guide
        if let exJSON = traits.first(where: { $0.dimension == "curated_examples" })?.value,
           let data = exJSON.data(using: .utf8),
           let examples = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            for (i, ex) in examples.prefix(8).enumerated() {
                let rawCtx = ex["context"] ?? ""
                let ctx = Self.contextNameMap[rawCtx] ?? rawCtx
                let text = ex["text"] ?? ""
                let truncated = text.count > 60 ? String(text.prefix(60)) + "…" : text
                lines.append("\(i + 1). \(ctx)「\(truncated)」")
            }
        } else if !samples.isEmpty {
            // Fallback to recent writing samples
            for (i, sample) in samples.prefix(8).enumerated() {
                let preview = String(sample.content.prefix(60))
                let ctx = Self.contextNameMap[sample.context] ?? sample.context
                lines.append("\(i + 1). \(ctx)「\(preview)」")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Layer 5: Values & Priorities

    private func formatLayer5(traits: [ValueTrait]) -> String {
        let lines = traits
            .filter { $0.confidence >= 0.5 }
            .compactMap { $0.description ?? Self.fallbackDescribe($0.dimension, value: $0.value) }
            .map { "- \($0)" }

        return lines.isEmpty ? "No values data" : lines.joined(separator: "\n")
    }

    // MARK: - Activity Logs

    private func formatActivityLogs(_ records: [ActivityRecord]) -> String {
        guard !records.isEmpty else { return "No recent activity records" }

        var lines: [String] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd HH:mm"

        for record in records {
            let time = dateFormatter.string(from: record.timestamp)
            let summary = record.contentSummary ?? record.windowTitle
            let topicsStr = record.topics.isEmpty ? "" : " [topics: \(record.topics.joined(separator: ", "))]"
            lines.append("- \(time) | \(record.appName) | \(summary)\(topicsStr)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Knowledge Graph

    private func formatKnowledgeGraph(nodes: [KnowledgeNode], edges: [KnowledgeEdge]) -> String {
        guard !nodes.isEmpty else { return "No knowledge graph data" }

        var lines: [String] = []

        lines.append("Core topic nodes:")
        for node in nodes {
            let hours = String(format: "%.1f", Double(node.totalTimeSpent) / 3600.0)
            lines.append("- \(node.topic) (\(node.category)): Total \(hours) hr, \(node.visitCount) visits, depth \(String(format: "%.2f", node.depthScore))")
        }

        if !edges.isEmpty {
            let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.topic) })
            lines.append("\nAssociations:")
            for edge in edges {
                let source = nodeMap[edge.sourceNodeId] ?? edge.sourceNodeId
                let target = nodeMap[edge.targetNodeId] ?? edge.targetNodeId
                lines.append("- \(source) <-> \(target) (strength \(String(format: "%.2f", edge.strength)), \(edge.coOccurrenceCount) co-occurrences)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
