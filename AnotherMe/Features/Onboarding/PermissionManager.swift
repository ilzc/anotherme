import Foundation
import ScreenCaptureKit
import ApplicationServices

enum PermissionStatus {
    case granted
    case notDetermined
    case denied
}

@Observable
final class PermissionManager {
    var screenRecordingStatus: PermissionStatus = .notDetermined
    var accessibilityStatus: PermissionStatus = .notDetermined

    var allPermissionsGranted: Bool {
        screenRecordingStatus == .granted && accessibilityStatus == .granted
    }

    // MARK: - Check Permissions

    func checkAll() async {
        await checkScreenRecording()
        checkAccessibility()
    }

    func checkScreenRecording() async {
        do {
            _ = try await SCShareableContent.current
            screenRecordingStatus = .granted
        } catch {
            screenRecordingStatus = .denied
        }
    }

    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        accessibilityStatus = trusted ? .granted : .denied
    }

    // MARK: - Request Permissions

    func requestAccessibility() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Polling for permission changes

    /// Polls for permission changes up to `maxRetries` times (default 300 = 5 minutes).
    /// Returns `true` if all permissions were granted, `false` if timed out.
    @discardableResult
    func waitForPermissions(maxRetries: Int = 300) async -> Bool {
        var retries = 0
        while !allPermissionsGranted && retries < maxRetries {
            try? await Task.sleep(for: .seconds(1))
            await checkAll()
            retries += 1
        }
        return allPermissionsGranted
    }
}
