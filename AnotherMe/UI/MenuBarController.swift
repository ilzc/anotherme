import AppKit
import SwiftUI

/// Manages the menu bar status item and its dropdown menu.
/// Dynamically updates status and capture count from AppState.
@MainActor
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem!
    private let appState = AppState.shared

    // Menu items that need dynamic updates
    private var statusMenuItem: NSMenuItem!
    private var captureCountMenuItem: NSMenuItem!
    private var toggleCaptureMenuItem: NSMenuItem!

    // Callbacks
    var openMainWindow: (() -> Void)?
    var openSettings: (() -> Void)?
    var toggleFloatingAssistant: (() -> Void)?

    // Notification observer for capture-completed flash
    private var captureObserver: NSObjectProtocol?

    // Icon names (SF Symbols)
    private let normalIconName = "brain.head.profile"
    private let activeIconName = "brain.head.profile.fill"

    // MARK: - Icon Helper

    /// Builds a properly configured menu bar icon from an SF Symbol name.
    /// Uses `isTemplate = true` so macOS automatically adapts the tint
    /// for both light and dark menu bar appearances.
    private func makeMenuBarIcon(symbolName: String, accessibilityDescription: String = "AnotherMe") -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium, scale: .medium)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(config) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = makeMenuBarIcon(symbolName: normalIconName)
        }

        buildMenu()

        // Observe state changes for dynamic menu updates
        startObserving()

        // Observe capture-completed notifications to flash the icon
        captureObserver = NotificationCenter.default.addObserver(
            forName: .captureCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flashIcon()
        }
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        let menu = NSMenu()

        // "Open AnotherMe"
        let openItem = NSMenuItem(title: "Open AnotherMe", action: #selector(handleOpenMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        // Status line (dynamic)
        statusMenuItem = NSMenuItem(title: "Status: Capturing", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        // Today capture count (dynamic)
        captureCountMenuItem = NSMenuItem(title: "Captured Today: 0", action: nil, keyEquivalent: "")
        captureCountMenuItem.isEnabled = false
        menu.addItem(captureCountMenuItem)

        menu.addItem(.separator())

        // Toggle capture
        toggleCaptureMenuItem = NSMenuItem(title: "Pause Capture", action: #selector(handleToggleCapture), keyEquivalent: "")
        toggleCaptureMenuItem.target = self
        menu.addItem(toggleCaptureMenuItem)

        // Toggle floating assistant
        let assistantItem = NSMenuItem(title: "Show/Hide Assistant", action: #selector(handleToggleFloatingAssistant), keyEquivalent: "")
        assistantItem.target = self
        menu.addItem(assistantItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(handleOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Dynamic Updates

    private var observationTask: Task<Void, Never>?

    private func startObserving() {
        // Poll state periodically to update menu items.
        // Using a Task loop since NSMenu items are not SwiftUI-reactive.
        observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updateMenuItems()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @MainActor
    private func updateMenuItems() {
        guard let captureService = appState.captureService else { return }

        let isRunning = captureService.isRunning
        let count = captureService.todayCaptureCount

        statusMenuItem.title = isRunning ? "Status: Capturing" : "Status: Paused"
        captureCountMenuItem.title = "Captured Today: \(count)"
        toggleCaptureMenuItem.title = isRunning ? "Pause Capture" : "Resume Capture"
    }

    // MARK: - Flash Icon (Capture Feedback)

    /// Briefly highlights the menu bar icon for 0.3s to indicate a capture occurred.
    @MainActor
    func flashIcon() {
        guard let button = statusItem.button else { return }
        button.image = makeMenuBarIcon(symbolName: activeIconName, accessibilityDescription: "AnotherMe capturing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            button.image = makeMenuBarIcon(symbolName: normalIconName)
        }
    }

    // MARK: - Actions

    @objc private func handleOpenMainWindow() {
        openMainWindow?()
    }

    @objc private func handleOpenSettings() {
        openSettings?()
    }

    @objc private func handleToggleFloatingAssistant() {
        toggleFloatingAssistant?()
    }

    @objc private func handleToggleCapture() {
        if appState.captureService?.isRunning == true {
            appState.stopCapture()
        } else {
            appState.startCapture()
        }
        updateMenuItems()
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }

    deinit {
        observationTask?.cancel()
        if let captureObserver {
            NotificationCenter.default.removeObserver(captureObserver)
        }
    }
}
