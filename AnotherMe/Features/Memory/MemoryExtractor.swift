import Foundation

/// Extracts memory points from screenshot analysis results.
/// Called within the AnalysisPipeline after successful analysis.
struct MemoryExtractor {
    let memoryStore: MemoryStore

    /// Extract and store memory points from a screenshot analysis.
    /// Filters out low-value activities (idle/browsing) and rewrites content to first-person.
    func extractAndStore(from analysis: ScreenshotAnalysis, activityId: String) {
        // Build memory from topics + content summary
        guard !analysis.topics.isEmpty else { return }

        // Skip low-value activities — idle and casual browsing aren't worth remembering
        let engagement = analysis.engagementLevel
        guard engagement != "idle" && engagement != "browsing" else { return }

        let keywords: [String] = analysis.topics
        guard let keywordsJSON = try? JSONEncoder().encode(keywords),
              let keywordsStr = String(data: keywordsJSON, encoding: .utf8) else { return }

        // Rewrite content to first-person perspective
        let content = toFirstPerson(analysis.contentSummary)

        let memory = Memory(
            content: content,
            category: categorize(analysis),
            keywords: keywordsStr,
            importance: importanceScore(analysis),
            sourceType: "activity",
            sourceId: activityId
        )

        do {
            try memoryStore.insertOrMerge(memory)
        } catch {
            print("[MemoryExtractor] Failed to store memory: \(error)")
        }
    }

    /// Rewrites third-person observation ("The user is ...") to first-person ("...").
    private func toFirstPerson(_ text: String) -> String {
        var result = text
        // Remove common third-person prefixes (longest first to avoid partial matches)
        let prefixes = ["The user is currently ", "The user is ", "User is currently ", "User is ", "The user ", "User "]
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                // Lowercase the first character (the verb) after stripping the prefix
                if let first = result.first, first.isUppercase {
                    result = first.lowercased() + result.dropFirst()
                }
                break
            }
        }
        return result
    }

    private func categorize(_ analysis: ScreenshotAnalysis) -> String {
        switch analysis.activityCategory {
        case "learning": return "topic"
        case "work": return "topic"
        case "creative": return "topic"
        case "social": return "intent"
        case "entertainment": return "habit"
        default: return "topic"
        }
    }

    private func importanceScore(_ analysis: ScreenshotAnalysis) -> Double {
        switch analysis.engagementLevel {
        case "deep_focus": return 0.8
        case "active_work": return 0.6
        case "browsing": return 0.3
        case "idle": return 0.1
        default: return 0.5
        }
    }
}
