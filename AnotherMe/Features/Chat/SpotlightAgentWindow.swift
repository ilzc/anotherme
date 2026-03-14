import SwiftUI
import AppKit

@MainActor
final class SpotlightAgentWindow {
    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            showCentered()
        }
    }

    func showCentered() {
        if panel == nil {
            createPanel()
        }
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.midY + screenFrame.height * 0.15
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        p.contentView = NSHostingView(rootView: SpotlightChatView())
        p.isReleasedWhenClosed = false
        panel = p
    }
}

// MARK: - Spotlight Chat View

/// Minimal chat view for the floating Spotlight window.
struct SpotlightChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var initialized = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.messages) { msg in
                        MessageBubbleView(message: msg)
                    }
                    if viewModel.isGenerating {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Thinking...").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding()
            }

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Ask me anything...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .onSubmit { Task { await viewModel.send() } }

                Button(action: { Task { await viewModel.send() } }) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(
                    viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.isGenerating
                )
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 300)
        .task {
            guard !initialized else { return }
            initialized = true

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

            let agentService = AgentService(
                router: router, promptBuilder: promptBuilder,
                dataProvider: dataProvider, aiClient: aiClient, chatStore: chatStore
            )

            // Reuse most recent session or create a new one
            let sessions = (try? chatStore.fetchSessions(limit: 1)) ?? []
            viewModel.setup(agentService: agentService, chatStore: chatStore)
            if let session = sessions.first {
                viewModel.selectSession(session.id)
            } else {
                viewModel.createNewSession()
            }
        }
    }
}
