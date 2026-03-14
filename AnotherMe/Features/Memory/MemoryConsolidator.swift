import Foundation

/// Consolidates low-importance memories by grouping them by month and using AI
/// to produce thematic summaries. Runs as part of the daily cleanup cycle,
/// before hard pruning kicks in.
final class MemoryConsolidator: @unchecked Sendable {
    private let memoryStore: MemoryStore
    private let aiClient: AIFallbackClient

    init(memoryStore: MemoryStore, aiClient: AIFallbackClient = .shared) {
        self.memoryStore = memoryStore
        self.aiClient = aiClient
    }

    /// Consolidate low-value memories when the total count exceeds the soft limit.
    /// - Parameter softLimit: Trigger consolidation when total count exceeds this.
    func consolidateIfNeeded(softLimit: Int = 250) async throws {
        let candidates = try memoryStore.fetchConsolidationCandidates(keepTop: softLimit)
        guard candidates.count >= 5 else { return } // Not worth consolidating fewer than 5

        // Group by calendar month
        let grouped = Dictionary(grouping: candidates) { memory -> String in
            let comps = Calendar.current.dateComponents([.year, .month], from: memory.createdAt)
            return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        }

        for (monthKey, memories) in grouped {
            guard memories.count >= 3 else { continue } // Skip months with too few to consolidate

            do {
                let summaries = try await summarize(memories: memories, monthKey: monthKey)
                guard !summaries.isEmpty else { continue }

                // Atomically replace originals with consolidated summaries
                try memoryStore.replaceWithConsolidated(
                    deleteIDs: memories.map(\.id),
                    insert: summaries
                )
            } catch {
                // AI failure for one month shouldn't block others; log and continue.
                print("[MemoryConsolidator] Failed to consolidate \(monthKey): \(error.localizedDescription)")
                continue
            }
        }
    }

    /// Force consolidation of all eligible memories, ignoring count threshold and recency window.
    /// Returns (consolidated count, original count) for UI feedback.
    func forceConsolidate() async throws -> (consolidated: Int, originals: Int) {
        let candidates = try memoryStore.fetchAllConsolidationCandidates()
        guard candidates.count >= 3 else { return (0, 0) }

        var totalConsolidated = 0
        var totalOriginals = 0

        let grouped = Dictionary(grouping: candidates) { memory -> String in
            let comps = Calendar.current.dateComponents([.year, .month], from: memory.createdAt)
            return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        }

        for (monthKey, memories) in grouped {
            guard memories.count >= 3 else { continue }

            do {
                let summaries = try await summarize(memories: memories, monthKey: monthKey)
                guard !summaries.isEmpty else { continue }

                try memoryStore.replaceWithConsolidated(
                    deleteIDs: memories.map(\.id),
                    insert: summaries
                )
                totalConsolidated += summaries.count
                totalOriginals += memories.count
            } catch {
                print("[MemoryConsolidator] Force consolidate \(monthKey) failed: \(error.localizedDescription)")
                continue
            }
        }

        return (totalConsolidated, totalOriginals)
    }

    // MARK: - AI Summarization

    private func summarize(memories: [Memory], monthKey: String) async throws -> [Memory] {
        let memoriesText = memories.enumerated().map { i, m in
            "[\(i + 1)] \(m.content) (keywords: \(m.parsedKeywords.joined(separator: ", ")))"
        }.joined(separator: "\n")

        let prompt = """
        Below are \(memories.count) personal memory fragments recorded during \(monthKey). Please consolidate them into 1-\(min(5, max(2, memories.count / 3))) independent summary memories grouped by theme.

        Requirements:
        1. Each summary should focus on one theme, written in first person
        2. Preserve important events and key details — don't just record recurring patterns
        3. Each summary must include keywords (JSON array) and category (one of: topic/intent/habit/opinion/milestone)

        Memory fragments:
        \(memoriesText)

        Output in the following JSON format:
        [{"content": "...", "keywords": ["..."], "category": "..."}]
        """

        let (response, _) = try await aiClient.chatCompletion(
            functionName: AIModelSlot.deepAnalysis,
            debugFunction: "memory_consolidation"
        ) { slot in
            ChatCompletionRequest(
                model: slot.modelName,
                messages: [
                    .init(role: "system", content: [.text("You are a memory consolidation assistant. Organize scattered memory fragments into clearly themed summaries. Output pure JSON." + languageDirective(currentResponseLanguage()))]),
                    .init(role: "user", content: [.text(prompt)])
                ],
                temperature: 0.3,
                responseFormat: .json
            )
        }

        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            return []
        }

        let parsed = try JSONDecoder().decode([ConsolidationOutput].self, from: data)

        // Derive consolidated memory properties from the source group
        let maxImportance = memories.map(\.importance).max() ?? 0.5
        let earliestDate = memories.map(\.createdAt).min() ?? .now

        return parsed.map { item in
            let keywordsJSON = (try? JSONEncoder().encode(item.keywords))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

            return Memory(
                content: item.content,
                category: item.category,
                keywords: keywordsJSON,
                importance: min(maxImportance + 0.1, 1.0),
                sourceType: "consolidation",
                isConsolidated: true,
                createdAt: earliestDate,
                lastAccessedAt: .now
            )
        }
    }
}

// MARK: - AI Response Model

private struct ConsolidationOutput: Decodable {
    let content: String
    let keywords: [String]
    let category: String
}
