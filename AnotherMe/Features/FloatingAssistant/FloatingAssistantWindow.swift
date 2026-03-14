import AppKit
import SwiftUI

/// Non-activating floating panel that hosts the assistant ball and bubble.
@MainActor
final class FloatingAssistantWindow {

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    // The root view model – owned by the controller and passed in
    private let viewModel: FloatingAssistantViewModel

    // Ball size constants
    private static let ballSize: CGFloat = 76
    private static let expandedWidth: CGFloat = 280
    private static let expandedHeight: CGFloat = 220

    private var screenObserver: Any?
    /// Origin of the panel at the start of the current drag.
    private var dragStartOrigin: NSPoint?
    /// Mouse screen position at the start of the current drag.
    private var dragStartMouse: NSPoint?

    init(viewModel: FloatingAssistantViewModel) {
        self.viewModel = viewModel
        createPanel()
        observeScreenChanges()
    }

    // MARK: - Panel Creation

    private func createPanel() {
        let size = Self.ballSize
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isRestorable = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovableByWindowBackground = false // we handle drag ourselves via SwiftUI
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let rootView = FloatingAssistantRootView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.frame = p.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        p.contentView?.addSubview(hosting)

        self.hostingView = hosting
        self.panel = p

        restorePosition()
    }

    // MARK: - Show / Hide

    func show() {
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Resizing for Bubble

    /// Whether the ball is on the left half of the screen (bubble should expand right).
    private var isBallOnLeftEdge: Bool {
        guard let panel, let screen = currentScreen() else { return false }
        let screenMidX = screen.visibleFrame.midX
        return panel.frame.midX < screenMidX
    }

    func setBubbleExpanded(_ expanded: Bool) {
        guard let panel else { return }
        let ballSize = Self.ballSize
        let onLeft = isBallOnLeftEdge

        // Update the root view's bubble direction
        viewModel.bubbleExpandsRight = onLeft

        if expanded {
            let currentFrame = panel.frame
            let newWidth = Self.expandedWidth + ballSize
            let newHeight = max(Self.expandedHeight, ballSize)
            let newX: CGFloat
            if onLeft {
                // Ball on left edge: keep left origin, expand rightward
                newX = currentFrame.minX
            } else {
                // Ball on right edge: expand leftward, keep right edge pinned
                newX = currentFrame.maxX - newWidth
            }
            let newY = currentFrame.midY - newHeight / 2

            let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
            panel.setFrame(newFrame, display: true, animate: true)
        } else {
            let currentFrame = panel.frame
            let newX: CGFloat
            if onLeft {
                newX = currentFrame.minX
            } else {
                newX = currentFrame.maxX - ballSize
            }
            let newY = currentFrame.midY - ballSize / 2
            let newFrame = NSRect(x: newX, y: newY, width: ballSize, height: ballSize)
            panel.setFrame(newFrame, display: true, animate: true)
        }
    }

    // MARK: - Position & Edge Snap

    func snapToNearestEdge() {
        guard let panel, let screen = currentScreen() else { return }
        let frame = panel.frame
        let visibleFrame = screen.visibleFrame

        let distanceToLeft = frame.minX - visibleFrame.minX
        let distanceToRight = visibleFrame.maxX - frame.maxX

        var newOrigin = frame.origin

        if distanceToLeft <= distanceToRight {
            newOrigin.x = visibleFrame.minX + 4
        } else {
            newOrigin.x = visibleFrame.maxX - frame.width - 4
        }

        // Clamp Y
        newOrigin.y = max(visibleFrame.minY + 4, min(newOrigin.y, visibleFrame.maxY - frame.height - 4))

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(newOrigin)
        }

        savePosition()
    }

    func updateDrag(translation: CGSize) {
        guard let panel else { return }
        // Use NSEvent.mouseLocation (screen coordinates) instead of SwiftUI translation.
        // SwiftUI's .global coordinate space is window-relative, so it shifts when the
        // window moves — causing a feedback loop where the ball can't keep up with the mouse.
        let currentMouse = NSEvent.mouseLocation
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
            dragStartMouse = currentMouse
        }
        guard let startOrigin = dragStartOrigin,
              let startMouse = dragStartMouse else { return }
        let newOrigin = NSPoint(
            x: startOrigin.x + (currentMouse.x - startMouse.x),
            y: startOrigin.y + (currentMouse.y - startMouse.y)
        )
        panel.setFrameOrigin(newOrigin)
    }

    func endDrag() {
        dragStartOrigin = nil
        dragStartMouse = nil
    }

    func savePosition() {
        guard let panel else { return }
        // Save the right edge X and center Y (so collapsed vs expanded doesn't matter)
        let frame = panel.frame
        AssistantSettings.positionX = Double(frame.maxX - Self.ballSize / 2)
        AssistantSettings.positionY = Double(frame.midY)
    }

    private func restorePosition() {
        guard let panel else { return }
        let savedX = AssistantSettings.positionX
        let savedY = AssistantSettings.positionY

        if savedX >= 0, savedY >= 0, let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            // Position the ball centered on saved coordinates
            var x = CGFloat(savedX) - Self.ballSize / 2
            var y = CGFloat(savedY) - Self.ballSize / 2

            // Clamp to screen bounds
            x = max(visibleFrame.minX, min(x, visibleFrame.maxX - Self.ballSize))
            y = max(visibleFrame.minY, min(y, visibleFrame.maxY - Self.ballSize))

            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            // Default: right edge, vertically centered
            if let screen = NSScreen.main {
                let visibleFrame = screen.visibleFrame
                let x = visibleFrame.maxX - Self.ballSize - 4
                let y = visibleFrame.midY - Self.ballSize / 2
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
    }

    private func currentScreen() -> NSScreen? {
        guard let panel else { return NSScreen.main }
        // Find screen that contains the panel center
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        return NSScreen.screens.first(where: { NSPointInRect(center, $0.frame) }) ?? NSScreen.main
    }

    // MARK: - Screen Changes

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.validatePosition()
            }
        }
    }

    private func validatePosition() {
        guard let panel, let screen = currentScreen() ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        var origin = panel.frame.origin

        // Clamp to visible area
        origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - panel.frame.width))
        origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - panel.frame.height))

        panel.setFrameOrigin(origin)
        savePosition()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }
}

// MARK: - Root SwiftUI View

/// Combines the character ball and optional bubble in one SwiftUI hierarchy.
/// The ball is always pinned to the right side of the view.
struct FloatingAssistantRootView: View {
    @Bindable var viewModel: FloatingAssistantViewModel

    private var bubbleView: some View {
        AssistantBubbleView(
            isCaptureRunning: viewModel.isCaptureRunning,
            isSetupComplete: viewModel.isSetupComplete,
            onChat: viewModel.onChat ?? {},
            onToggleCapture: viewModel.onToggleCapture ?? {},
            onOpenMainWindow: viewModel.onOpenMainWindow ?? {},
            onOpenSettings: viewModel.onOpenSettings ?? {}
        )
    }

    private var characterView: some View {
        AssistantCharacterView(
            state: viewModel.characterState,
            onTap: { viewModel.tapAction?() },
            onDoubleTap: { viewModel.doubleTapAction?() },
            isDragging: viewModel.isDragging
        )
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    viewModel.isDragging = true
                    viewModel.dragAction?(value.translation)
                }
                .onEnded { _ in
                    viewModel.isDragging = false
                    viewModel.dragEndAction?()
                }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            if viewModel.bubbleExpandsRight {
                // Ball on left edge: ball first, then bubble to the right
                characterView
                if viewModel.isBubbleVisible {
                    bubbleView
                        .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
                }
            } else {
                // Ball on right edge: bubble to the left, then ball
                if viewModel.isBubbleVisible {
                    bubbleView
                        .transition(.scale(scale: 0.5, anchor: .trailing).combined(with: .opacity))
                }
                characterView
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.isBubbleVisible)
    }
}

// MARK: - ViewModel

/// Observable model shared between the SwiftUI view and the controller.
@MainActor
@Observable
final class FloatingAssistantViewModel {
    var characterState: AssistantCharacterState = .idle
    var isBubbleVisible = false
    var bubbleExpandsRight = false
    var isCaptureRunning = false
    var isSetupComplete = false
    var isDragging = false

    // Action callbacks – set by the controller
    var tapAction: (() -> Void)?
    var doubleTapAction: (() -> Void)?
    var dragAction: ((CGSize) -> Void)?
    var dragEndAction: (() -> Void)?
    var onChat: (() -> Void)?
    var onToggleCapture: (() -> Void)?
    var onOpenMainWindow: (() -> Void)?
    var onOpenSettings: (() -> Void)?
}
