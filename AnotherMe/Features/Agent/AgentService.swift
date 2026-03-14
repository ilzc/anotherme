import Foundation

/// Main service orchestrating the Agent conversation flow:
/// synthesize persona -> route -> fetch context -> build prompt -> call LLM -> persist.
@MainActor
@Observable
final class AgentService {

    private let router: QueryRouter
    private let promptBuilder: AgentPromptBuilder
    private let dataProvider: LayerDataProvider
    private let aiClient: AIClient
    private let chatStore: ChatStore
    private let memoryRetriever: MemoryRetriever?
    private let personaSynthesizer: PersonaSynthesizer?

    private(set) var isGenerating = false

    init(
        router: QueryRouter,
        promptBuilder: AgentPromptBuilder,
        dataProvider: LayerDataProvider,
        aiClient: AIClient,
        chatStore: ChatStore,
        memoryRetriever: MemoryRetriever? = nil,
        personaSynthesizer: PersonaSynthesizer? = nil
    ) {
        self.router = router
        self.promptBuilder = promptBuilder
        self.dataProvider = dataProvider
        self.aiClient = aiClient
        self.chatStore = chatStore
        self.memoryRetriever = memoryRetriever
        self.personaSynthesizer = personaSynthesizer
    }

    // MARK: - Errors

    enum AgentError: Error, LocalizedError {
        case modelNotConfigured(String)

        var errorDescription: String? {
            switch self {
            case .modelNotConfigured(let slot):
                return "AI model not configured: \(slot)"
            }
        }
    }

    // MARK: - Send Message

    func sendMessage(_ text: String, sessionId: String) async throws -> [ChatMessage] {
        isGenerating = true
        defer { isGenerating = false }

        // 1. Save user message & load history
        let chatStore = self.chatStore
        let (history, _) = try await Task.detached {
            let userMsg = ChatMessage(
                sessionId: sessionId,
                role: "user",
                content: text
            )
            try chatStore.insertMessage(userMsg)
            let history = try chatStore.fetchRecentMessages(sessionId: sessionId, limit: 10)
            return (history, userMsg)
        }.value

        // 2. Route + fetch persona narrative + fetch context + recall memories (parallel)
        let routeResult = try await router.route(question: text, recentMessages: history)

        async let narrativeTask = personaSynthesizer?.fetchOrGenerate()
        async let styleGuideTask = personaSynthesizer?.fetchOrGenerateStyleGuide()
        async let contextTask = dataProvider.fetchData(for: routeResult)

        let narrative = try await narrativeTask
        let styleGuide = try await styleGuideTask
        let contextData = try await contextTask

        // 2.5 Recall memories
        var memoriesText: String?
        if let retriever = memoryRetriever {
            let memories = try await Task.detached {
                try retriever.recall(query: text)
            }.value
            memoriesText = MemoryRetriever.formatMemories(memories)
        }

        // 3. Build prompt
        let systemPrompt = promptBuilder.build(
            narrative: narrative,
            styleGuide: styleGuide,
            supplemental: contextData,
            memories: memoriesText,
            routeResult: routeResult
        )

        // 4. Call LLM
        let chatMessages = buildMessages(systemPrompt: systemPrompt, history: history)
        let (response, _) = try await AIFallbackClient.shared.chatCompletion(
            functionName: AIModelSlot.chat,
            debugFunction: "chat"
        ) { slot in
            ChatCompletionRequest(
                model: slot.modelName,
                messages: chatMessages,
                temperature: slot.temperature,
                responseFormat: nil
            )
        }
        let content = response.choices.first?.message.content ?? "Sorry, I'm unable to respond right now."

        // Split response into multiple messages if delimiter is present
        let messageParts = Self.splitResponse(content)

        // 5. Save reply (may be multiple messages for multi-message scenarios)
        let agentMsgs: [ChatMessage] = try await Task.detached {
            var msgs: [ChatMessage] = []
            for part in messageParts {
                let agentMsg = ChatMessage(
                    sessionId: sessionId,
                    role: "agent",
                    content: part,
                    referencedLayers: routeResult.layersNeeded
                )
                try chatStore.insertMessage(agentMsg)
                msgs.append(agentMsg)
            }
            return msgs
        }.value

        return agentMsgs
    }

    // MARK: - Response Splitting

    /// Splits a response on `---` delimiters into multiple message parts.
    /// Used for multi-message scenarios (e.g., WeChat-style replies).
    private static func splitResponse(_ content: String) -> [String] {
        let parts = content.components(separatedBy: "\n---\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [content] : parts
    }

    // MARK: - Message Assembly

    private func buildMessages(
        systemPrompt: String,
        history: [ChatMessage]
    ) -> [ChatCompletionRequest.Message] {
        var messages: [ChatCompletionRequest.Message] = [
            .init(role: "system", content: [.text(systemPrompt)])
        ]

        for msg in history.suffix(10) {
            let role = msg.role == "user" ? "user" : "assistant"
            messages.append(.init(role: role, content: [.text(msg.content)]))
        }

        return messages
    }
}
