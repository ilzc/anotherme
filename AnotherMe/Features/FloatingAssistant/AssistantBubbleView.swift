import SwiftUI

/// Speech bubble with 4 quick-action buttons, shown next to the floating ball.
struct AssistantBubbleView: View {
    let isCaptureRunning: Bool
    let isSetupComplete: Bool

    var onChat: () -> Void = {}
    var onToggleCapture: () -> Void = {}
    var onOpenMainWindow: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            // 2x2 grid of quick actions
            HStack(spacing: 12) {
                quickActionButton(
                    title: "Chat",
                    icon: "bubble.left.and.bubble.right.fill",
                    enabled: isSetupComplete
                ) {
                    onChat()
                }

                quickActionButton(
                    title: isCaptureRunning ? "Pause Capture" : "Resume Capture",
                    icon: isCaptureRunning ? "pause.circle" : "play.circle",
                    enabled: isSetupComplete
                ) {
                    onToggleCapture()
                }
            }

            HStack(spacing: 12) {
                quickActionButton(
                    title: "Main Window",
                    icon: "macwindow",
                    enabled: true
                ) {
                    onOpenMainWindow()
                }

                quickActionButton(
                    title: "Settings",
                    icon: "gearshape",
                    enabled: true
                ) {
                    onOpenSettings()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Actions")
    }

    private func quickActionButton(
        title: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(height: 24)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 100, height: 60)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
