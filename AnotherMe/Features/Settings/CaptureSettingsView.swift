import SwiftUI
import ServiceManagement

struct CaptureSettingsView: View {
    @AppStorage(SettingsKey.intervalSeconds) private var intervalSeconds = 300
    @AppStorage(SettingsKey.eventDrivenEnabled) private var eventEnabled = true
    @AppStorage(SettingsKey.smartSamplingEnabled) private var smartEnabled = true
    @AppStorage(SettingsKey.captureAnimationEnabled) private var animationEnabled = true
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = false

    var body: some View {
        ScrollView {
        Form {
            Section("Minimum Capture Interval") {
                Picker("Interval", selection: $intervalSeconds) {
                    Text("1 min").tag(60)
                    Text("3 min").tag(180)
                    Text("5 min").tag(300)
                    Text("10 min").tag(600)
                    Text("15 min").tag(900)
                }
                Text("Shared across all capture modes. Minimum time between two consecutive captures.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Event-Driven") {
                Toggle("Capture on app switch", isOn: $eventEnabled)
            }

            Section("Smart Sampling") {
                Toggle("Auto-adjust frequency based on activity level", isOn: $smartEnabled)
            }

            Section("Feedback") {
                Toggle("Show animation on capture", isOn: $animationEnabled)
            }

            Section("Display") {
                Text("Primary display by default")
                    .foregroundStyle(.secondary)
            }

            if !eventEnabled && !smartEnabled {
                Section {
                    Text("⚠ Both event-driven and smart sampling are disabled. Only interval-based capture is active.")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        }
    }

    // MARK: - Launch at Login

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert toggle on failure
            launchAtLogin = !enabled
        }
    }
}

#Preview {
    CaptureSettingsView()
}
