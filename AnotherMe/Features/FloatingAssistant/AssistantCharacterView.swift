import SwiftUI

/// The visual state of the floating assistant character.
enum AssistantCharacterState {
    case idle
    case observing
}

/// A 48x48 floating ball displaying a brain icon with frosted glass background.
/// Designed to be clearly visible on any desktop wallpaper.
struct AssistantCharacterView: View {
    let state: AssistantCharacterState
    var onTap: () -> Void = {}
    var onDoubleTap: () -> Void = {}
    var isDragging: Bool = false

    @State private var breathing = false
    @State private var glowOpacity: Double = 0
    @State private var isHovering = false

    private let ballSize: CGFloat = 64

    var body: some View {
        ZStack {
            // Drop shadow layer
            Circle()
                .fill(Color.black.opacity(0.18))
                .frame(width: ballSize, height: ballSize)
                .blur(radius: 8)
                .offset(y: 2)

            // Frosted glass background
            Circle()
                .fill(.regularMaterial)
                .frame(width: ballSize, height: ballSize)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                )

            // Observing glow ring
            Circle()
                .stroke(Color.blue, lineWidth: 2.5)
                .frame(width: ballSize + 5, height: ballSize + 5)
                .opacity(glowOpacity)

            // Brain icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.primary)
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                .scaleEffect(breathing ? 1.03 : 0.97)
        }
        .frame(width: 76, height: 76)
        // Hover & drag scale feedback
        .scaleEffect(isDragging ? 1.15 : (isHovering ? 1.08 : 1.0))
        .opacity(isDragging ? 0.85 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
        .contentShape(Circle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .onTapGesture(count: 1) {
            onTap()
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("AnotherMe Floating Assistant")
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.5).repeatForever(autoreverses: true)
            ) {
                breathing = true
            }
        }
        .onChange(of: state) { _, newState in
            if newState == .observing {
                withAnimation(.easeIn(duration: 0.15)) {
                    glowOpacity = 1.0
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                    glowOpacity = 0
                }
            }
        }
    }
}
