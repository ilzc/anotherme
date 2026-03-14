import Foundation

actor QueryRouter {
    private let aiClient: AIClient

    init(aiClient: AIClient = .shared) {
        self.aiClient = aiClient
    }

    func route(question: String, recentMessages: [ChatMessage]) async throws -> RouterResponse {
        let config = AIModelSlotStore.shared.load(name: AIModelSlot.router)
        guard config.isConfigured else {
            return defaultRoute(question: question)
        }

        let request = RouterPrompt.buildRequest(question: question, context: recentMessages)
        let response = try await aiClient.chatCompletion(config: config, request: request, debugFunction: "router")

        guard let content = response.choices.first?.message.content else {
            return defaultRoute(question: question)
        }

        do {
            return try JSONDecoder().decode(RouterResponse.self, from: Data(content.utf8))
        } catch {
            return defaultRoute(question: question)
        }
    }

    private func defaultRoute(question: String) -> RouterResponse {
        RouterResponse(
            intent: .selfAwareness,
            layersNeeded: [1, 2, 3, 4, 5],
            timeRange: "last_7_days",
            queryType: "general",
            specificQueries: [],
            needActivityLogs: true,
            needKnowledgeGraph: true,
            formatHint: nil
        )
    }
}
