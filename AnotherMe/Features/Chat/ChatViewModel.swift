import Foundation

@MainActor
@Observable
final class ChatViewModel {
    var sessions: [ChatSession] = []
    var currentSessionId: String?
    var messages: [ChatMessage] = []
    var inputText = ""
    var isGenerating = false
    var error: String?

    private var agentService: AgentService?
    private var chatStore: ChatStore?
    private var sendTask: Task<Void, Never>?
    /// HumanizedReplyManager is ready for future streaming UI integration.
    /// Currently messages are delivered instantly; when the UI supports
    /// segment-by-segment display, use replyManager.deliver() to animate replies.
    private let replyManager = HumanizedReplyManager()
    var humanizedEnabled: Bool = true

    func setup(agentService: AgentService, chatStore: ChatStore) {
        self.agentService = agentService
        self.chatStore = chatStore
        loadSessions()
    }

    func loadSessions() {
        guard let store = chatStore else { return }
        sessions = (try? store.fetchSessions()) ?? []
        if currentSessionId == nil, let first = sessions.first {
            currentSessionId = first.id
            loadMessages()
        }
    }

    func loadMessages() {
        guard let store = chatStore, let sessionId = currentSessionId else {
            messages = []
            return
        }
        messages = (try? store.fetchMessages(sessionId: sessionId)) ?? []
    }

    func createNewSession() {
        guard let store = chatStore else { return }
        do {
            let session = try store.createSession(title: "New Chat")
            sessions.insert(session, at: 0)
            currentSessionId = session.id
            messages = []
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteSession(_ id: String) {
        guard let store = chatStore else { return }
        do {
            try store.deleteSession(id: id)
            sessions.removeAll { $0.id == id }
            if currentSessionId == id {
                currentSessionId = sessions.first?.id
                loadMessages()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectSession(_ id: String) {
        sendTask?.cancel()
        currentSessionId = id
        loadMessages()
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let agent = agentService,
              let sessionId = currentSessionId else { return }

        inputText = ""
        isGenerating = true
        error = nil

        // Immediately show the user message in the UI before waiting for AI
        let userMsg = ChatMessage(
            sessionId: sessionId,
            role: "user",
            content: text
        )
        messages.append(userMsg)

        sendTask?.cancel()
        sendTask = Task {
            do {
                _ = try await agent.sendMessage(text, sessionId: sessionId)
                guard !Task.isCancelled, currentSessionId == sessionId else { return }
                loadMessages()
            } catch is CancellationError {
                // Task was cancelled (e.g., session switch) — no action needed
            } catch {
                self.error = error.localizedDescription
                guard currentSessionId == sessionId else { return }
                loadMessages()
            }
            isGenerating = false
        }
        await sendTask?.value
    }
}
