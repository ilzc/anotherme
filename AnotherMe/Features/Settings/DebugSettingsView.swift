import SwiftUI

struct DebugSettingsView: View {
    @AppStorage(DebugLogger.enabledKey) private var devModeEnabled = false
    @State private var logSize: String = "Calculating..."
    @State private var showClearConfirm = false

    var body: some View {
        ScrollView {
            Form {
                Section {
                    Toggle("Developer Mode", isOn: $devModeEnabled)
                        .onChange(of: devModeEnabled) { _, newValue in
                            if newValue {
                                DebugLogger.shared.startSession()
                            }
                        }
                } header: {
                    Text("Developer Mode")
                } footer: {
                    Text("When enabled, logs each capture's screenshot, all LLM requests/responses, and local database writes for debugging.")
                }

                if devModeEnabled {
                    Section("Log Info") {
                        LabeledContent("Storage Location") {
                            if let path = DebugLogger.shared.logDirectoryPath {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } else {
                                Text("Not initialized")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        LabeledContent("Log Size") {
                            Text(logSize)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button("Open in Finder") {
                                openLogDirectory()
                            }

                            Spacer()

                            Button("Clear All Logs", role: .destructive) {
                                showClearConfirm = true
                            }
                        }
                    }

                    Section("Logged Content") {
                        Label("Screenshot images (JPEG)", systemImage: "photo")
                        Label("LLM request parameters (excluding image base64)", systemImage: "arrow.up.doc")
                        Label("LLM responses + token usage + latency", systemImage: "arrow.down.doc")
                        Label("Local database write records", systemImage: "internaldrive")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { updateLogSize() }
        .alert("Confirm Clear", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) {
                DebugLogger.shared.clearAllLogs()
                updateLogSize()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All debug log files will be deleted. This cannot be undone.")
        }
    }

    private func updateLogSize() {
        let bytes = DebugLogger.shared.totalLogSize
        if bytes == 0 {
            logSize = "No logs"
        } else if bytes < 1024 * 1024 {
            logSize = String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else if bytes < 1024 * 1024 * 1024 {
            logSize = String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
        } else {
            logSize = String(format: "%.2f GB", Double(bytes) / 1024.0 / 1024.0 / 1024.0)
        }
    }

    private func openLogDirectory() {
        if let path = DebugLogger.shared.logDirectoryPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}

#Preview {
    DebugSettingsView()
}
