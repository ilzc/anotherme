import AppKit
import SwiftUI

/// Main coordinator for the floating desktop assistant.
/// Creates and manages the floating window, handles notifications,
/// and wires up all user actions.
@MainActor
final class FloatingAssistantController {

    private let viewModel = FloatingAssistantViewModel()
    private var window: FloatingAssistantWindow?

    /// Shared SpotlightAgentWindow — set from AppDelegate to avoid duplicate instances.
    var spotlightWindow: SpotlightAgentWindow?

    private var captureObserver: NSObjectProtocol?
    private var observingResetTask: Task<Void, Never>?
    private var statePollingTask: Task<Void, Never>?

    private let appState = AppState.shared

    // MARK: - Lifecycle

    init() {
        window = FloatingAssistantWindow(viewModel: viewModel)
        wireActions()
        observeCaptureNotifications()
        startStatePolling()

        // Show if previously visible (or first launch default)
        if AssistantSettings.isVisible {
            window?.show()
        }
    }

    // MARK: - Public API

    func toggleVisibility() {
        if let window, window.isVisible {
            window.hide()
            AssistantSettings.isVisible = false
            dismissBubble()
        } else {
            window?.show()
            AssistantSettings.isVisible = true
        }
    }

    // MARK: - Actions Wiring

    private func wireActions() {
        viewModel.tapAction = { [weak self] in
            self?.toggleBubble()
        }

        viewModel.doubleTapAction = { [weak self] in
            self?.openSpotlightChat()
        }

        viewModel.dragAction = { [weak self] (translation: CGSize) in
            self?.dismissBubble()
            self?.window?.updateDrag(translation: translation)
        }

        viewModel.dragEndAction = { [weak self] in
            self?.window?.endDrag()
            self?.dismissBubble()
            self?.window?.snapToNearestEdge()
        }

        viewModel.onChat = { [weak self] in
            self?.dismissBubble()
            self?.openSpotlightChat()
        }

        viewModel.onToggleCapture = { [weak self] in
            self?.toggleCapture()
        }

        viewModel.onOpenMainWindow = { [weak self] in
            self?.dismissBubble()
            self?.openMainWindow()
        }

        viewModel.onOpenSettings = { [weak self] in
            self?.dismissBubble()
            self?.openSettings()
        }
    }

    // MARK: - Bubble

    private func toggleBubble() {
        let newValue = !viewModel.isBubbleVisible
        viewModel.isBubbleVisible = newValue
        window?.setBubbleExpanded(newValue)
    }

    private func dismissBubble() {
        guard viewModel.isBubbleVisible else { return }
        viewModel.isBubbleVisible = false
        window?.setBubbleExpanded(false)
    }

    // MARK: - Quick Actions

    private func openSpotlightChat() {
        spotlightWindow?.toggle()
    }

    private func toggleCapture() {
        if appState.captureService?.isRunning == true {
            appState.stopCapture()
        } else {
            appState.startCapture()
        }
        // Update immediately
        viewModel.isCaptureRunning = appState.captureService?.isRunning ?? false
    }

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let mainWindow = NSApplication.shared.windows.first(where: { $0.title == "AnotherMe" }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let mainWindow = NSApplication.shared.windows.first(where: { $0.title == "AnotherMe" }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        // Settings is in the main window; bringing it to front is sufficient
    }

    // MARK: - Capture Observation

    private func observeCaptureNotifications() {
        captureObserver = NotificationCenter.default.addObserver(
            forName: .captureCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flashObserving()
            }
        }
    }

    private func flashObserving() {
        // Cancel any existing reset
        observingResetTask?.cancel()

        viewModel.characterState = .observing

        observingResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.viewModel.characterState = .idle
        }
    }

    // MARK: - State Polling

    /// Polls AppState periodically to keep the view model in sync.
    private func startStatePolling() {
        statePollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.viewModel.isSetupComplete = self.appState.isSetupComplete
                self.viewModel.isCaptureRunning = self.appState.captureService?.isRunning ?? false
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        statePollingTask?.cancel()
        observingResetTask?.cancel()
        if let captureObserver {
            NotificationCenter.default.removeObserver(captureObserver)
        }
    }
}
