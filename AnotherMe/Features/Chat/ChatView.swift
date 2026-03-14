import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()

    var body: some View {
        HSplitView {
            sessionList
            chatContent
        }
        .task {
            await initializeViewModel()
        }
    }

    // MARK: - Session List (Left Pane)

    private var sessionList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conversations")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.createNewSession() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Chat")
            }
            .padding(12)

            Divider()

            if viewModel.sessions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No conversations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tap + to start")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.sessions, selection: Binding(
                    get: { viewModel.currentSessionId },
                    set: { if let id = $0 { viewModel.selectSession(id) } }
                )) { session in
                    VStack(alignment: .leading) {
                        Text(session.title.isEmpty ? "New Chat" : session.title)
                            .lineLimit(1)
                        Text(session.createdAt, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            viewModel.deleteSession(session.id)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 200, maxWidth: 260)
    }

    // MARK: - Chat Content (Right Pane)

    private var chatContent: some View {
        VStack(spacing: 0) {
            if viewModel.currentSessionId == nil {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("Select or create a conversation")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Button("New Chat") {
                        viewModel.createNewSession()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else if viewModel.messages.isEmpty && !viewModel.isGenerating {
                messageEmptyState
                Divider()
                inputBar
            } else {
                messageList
                errorBanner
                Divider()
                inputBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty Message State

    private var messageEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("Start chatting")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Ask me anything about your behavioral patterns, interests, cognitive style, and more.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { msg in
                        MessageBubbleView(message: msg)
                            .id(msg.id)
                    }
                    if viewModel.isGenerating {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("loading")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isGenerating) { _, generating in
                if generating { scrollToBottom(proxy: proxy) }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.isGenerating {
            withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
        } else if let last = viewModel.messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let error = viewModel.error {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                Spacer()
                Button("Close") { viewModel.error = nil }
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit {
                    if !NSEvent.modifierFlags.contains(.shift) {
                        Task { await viewModel.send() }
                    }
                }

            Button(action: { Task { await viewModel.send() } }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(
                viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isGenerating
            )
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    // MARK: - Initialization

    private func initializeViewModel() async {
        let appState = AppState.shared
        guard let chatStore = appState.chatStore else { return }

        let aiClient = AIClient.shared
        let router = QueryRouter(aiClient: aiClient)
        let promptBuilder = AgentPromptBuilder()

        guard let activityStore = appState.activityStore else { return }
        guard let layer1Store = appState.layer1Store,
              let layer2Store = appState.layer2Store,
              let layer3Store = appState.layer3Store,
              let layer4Store = appState.layer4Store,
              let layer5Store = appState.layer5Store else { return }

        let dataProvider = LayerDataProvider(
            activityStore: activityStore,
            layer1Store: layer1Store,
            layer2Store: layer2Store,
            layer3Store: layer3Store,
            layer4Store: layer4Store,
            layer5Store: layer5Store
        )

        let personaSynthesizer = PersonaSynthesizer(
            layer3Store: layer3Store,
            layer4Store: layer4Store,
            layer5Store: layer5Store
        )

        let memoryRetriever: MemoryRetriever? = appState.memoryStore.map {
            MemoryRetriever(memoryStore: $0)
        }

        let agentService = AgentService(
            router: router,
            promptBuilder: promptBuilder,
            dataProvider: dataProvider,
            aiClient: aiClient,
            chatStore: chatStore,
            memoryRetriever: memoryRetriever,
            personaSynthesizer: personaSynthesizer
        )

        viewModel.setup(agentService: agentService, chatStore: chatStore)
    }
}
