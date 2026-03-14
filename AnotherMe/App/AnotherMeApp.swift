import SwiftUI

@main
struct AnotherMeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main window (opened from menu bar)
        Window("AnotherMe", id: "main") {
            RootView()
        }
    }
}

/// Root view that gates on permissions: shows PermissionCheckView until all
/// permissions are granted, then shows MainWindowView.
struct RootView: View {
    private let appState = AppState.shared

    var body: some View {
        Group {
            if appState.permissionManager.allPermissionsGranted {
                MainWindowView()
            } else {
                PermissionCheckView(
                    permissionManager: appState.permissionManager,
                    onAllGranted: {
                        // Permissions granted — start capture if not already running
                        if let captureService = appState.captureService, !captureService.isRunning {
                            appState.startCapture()
                            appState.scheduleDailyCleanup()
                            appState.startModeling()
                        }
                    }
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
