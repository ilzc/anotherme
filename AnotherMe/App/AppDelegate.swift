import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Menu bar controller — retained for the lifetime of the app.
    private var menuBarController: MenuBarController?
    /// Spotlight-style floating agent window (created lazily on main actor).
    private var spotlightWindow: SpotlightAgentWindow?
    /// Floating desktop assistant controller.
    private var floatingAssistantController: FloatingAssistantController?
    /// Global hotkey monitor.
    private var globalHotkeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up the native menu bar status item
        let controller = MenuBarController()
        controller.openMainWindow = {
            // Activate and bring the main window to front
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first(where: { $0.title == "AnotherMe" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        controller.openSettings = {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first(where: { $0.title == "AnotherMe" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        controller.toggleFloatingAssistant = { [weak self] in
            self?.floatingAssistantController?.toggleVisibility()
        }
        controller.setup()
        self.menuBarController = controller

        // Initialize floating desktop assistant
        let assistantController = FloatingAssistantController()
        self.floatingAssistantController = assistantController

        // Register global hotkey (Cmd+Shift+A) for Spotlight agent
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 0 {
                Task { @MainActor in
                    if self?.spotlightWindow == nil {
                        self?.spotlightWindow = SpotlightAgentWindow()
                    }
                    self?.spotlightWindow?.toggle()
                }
            }
        }

        // Share the SpotlightAgentWindow so the floating assistant reuses it
        Task { @MainActor [weak self] in
            if self?.spotlightWindow == nil {
                self?.spotlightWindow = SpotlightAgentWindow()
            }
            assistantController.spotlightWindow = self?.spotlightWindow
        }

        Task {
            do {
                try await AppState.shared.setup()

                if AppState.shared.permissionManager.allPermissionsGranted {
                    AppState.shared.startCapture()
                    AppState.shared.scheduleDailyCleanup()
                    AppState.shared.startModeling()
                }
            } catch {
                print("[AppDelegate] Setup failed: \(error.localizedDescription)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stopCapture()
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Launch at Login

    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[AppDelegate] Launch at login failed: \(error)")
        }
    }
}
