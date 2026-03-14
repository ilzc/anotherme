import SwiftUI

struct AIModelSettingsView: View {
    @State private var providers: [AIModelProvider] = []
    @State private var assignments: [String: AIFunctionAssignment] = [:]
    @State private var editingProvider: AIModelProvider?
    @State private var isAddingNew = false
    @State private var selectedLanguage: String = UserDefaults.standard.string(forKey: SettingsKey.responseLanguage) ?? ""

    private let store = AIModelSlotStore.shared
    private let functions = AIModelSlot.allFunctions

    private let languageOptions: [(value: String, label: String)] = [
        ("", "自动（跟随系统）"),
        ("Chinese", "中文"),
        ("English", "English"),
        ("Japanese", "日本語"),
        ("Korean", "한국어"),
        ("French", "Français"),
        ("German", "Deutsch"),
        ("Spanish", "Español"),
    ]

    var body: some View {
        ScrollView {
        Form {
            // MARK: - Response Language
            Section {
                Picker("AI 响应语言", selection: $selectedLanguage) {
                    ForEach(languageOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: SettingsKey.responseLanguage)
                }
            } header: {
                Text("Language")
            } footer: {
                Text("设置 AI 分析和对话回复使用的语言。\"自动\" 将跟随系统语言。")
            }

            // MARK: - Model Providers Section
            Section {
                if providers.isEmpty {
                    Text("No model configured. Tap the button below to add one.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }

                ForEach(providers) { provider in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName.isEmpty ? "Unnamed" : provider.displayName)
                                .fontWeight(.medium)
                            Text("\(provider.modelName) · \(hostFromEndpoint(provider.endpoint))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        let usageCount = assignments.values.filter { $0.providerID == provider.id }.count
                        if usageCount > 0 {
                            Text("Assigned to \(usageCount) functions")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }

                        Button {
                            editingProvider = provider
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)

                        Button(role: .destructive) {
                            deleteProvider(provider)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    let newProvider = AIModelProvider()
                    editingProvider = newProvider
                    isAddingNew = true
                } label: {
                    Label("Add Model Configuration", systemImage: "plus")
                }
            } header: {
                Text("Model Configuration")
            } footer: {
                Text("Add OpenAI-compatible API endpoints. Each can be reused by multiple functions.")
            }

            // MARK: - Function Assignments Section
            Section {
                ForEach(functions, id: \.name) { fn in
                    let assignment = assignments[fn.name] ?? AIFunctionAssignment(
                        temperature: fn.defaultTemperature
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fn.label)
                                    .fontWeight(.medium)
                                Text("Recommended: \(fn.recommendedType) (\(fn.recommendedModels))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Picker("", selection: Binding(
                                get: { assignment.providerID ?? "" },
                                set: { newValue in
                                    var a = assignment
                                    a.providerID = newValue.isEmpty ? nil : newValue
                                    assignments[fn.name] = a
                                    store.saveAssignment(a, for: fn.name)
                                }
                            )) {
                                Text("Not Selected").tag("")
                                ForEach(providers) { provider in
                                    Text(provider.displayName.isEmpty ? provider.modelName : provider.displayName)
                                        .tag(provider.id)
                                }
                            }
                            .frame(width: 200)
                        }

                        DisclosureGroup("Parameters") {
                            HStack {
                                Text("Temperature")
                                    .frame(width: 80, alignment: .leading)
                                Slider(
                                    value: Binding(
                                        get: { assignment.temperature },
                                        set: { val in
                                            var a = assignment
                                            a.temperature = val
                                            assignments[fn.name] = a
                                            store.saveAssignment(a, for: fn.name)
                                        }
                                    ),
                                    in: 0...2, step: 0.1
                                )
                                Text("\(assignment.temperature, specifier: "%.1f")")
                                    .monospacedDigit()
                                    .frame(width: 30)
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Function Assignment")
            } footer: {
                Text("Select model configuration for each function. One model can be assigned to multiple functions.")
            }
        }
        .formStyle(.grouped)
        }
        .onAppear { reload() }
        .sheet(item: $editingProvider) { provider in
            ProviderEditSheet(
                provider: provider,
                isNew: isAddingNew,
                onSave: { saved in
                    store.saveProvider(saved)
                    isAddingNew = false
                    editingProvider = nil
                    reload()
                },
                onCancel: {
                    isAddingNew = false
                    editingProvider = nil
                }
            )
        }
    }

    // MARK: - Helpers

    private func reload() {
        providers = store.loadProviders()
        assignments = store.loadAssignments()
    }

    private func deleteProvider(_ provider: AIModelProvider) {
        store.deleteProvider(id: provider.id)
        reload()
    }

    private func hostFromEndpoint(_ endpoint: String) -> String {
        URL(string: endpoint)?.host ?? endpoint
    }
}

// MARK: - Provider Edit Sheet

private struct ProviderEditSheet: View {
    @State var provider: AIModelProvider
    let isNew: Bool
    let onSave: (AIModelProvider) -> Void
    let onCancel: () -> Void

    @State private var customHeadersText = ""
    @State private var isTesting = false
    @State private var testResultMessage: String?
    @State private var testResultIsSuccess = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(isNew ? "Add Model Configuration" : "Edit Model Configuration")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Form {
                Section("Basic Info") {
                    TextField("Configuration Name", text: $provider.displayName)
                        .help("Give this configuration a recognizable name")

                    TextField("API Endpoint", text: $provider.endpoint)
                        .textContentType(.URL)

                    if !provider.endpoint.isEmpty {
                        if AIClient.isEmbeddingModel(provider.modelName) {
                            Text("Request URL: \(provider.endpoint) (Embedding does not auto-append path)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Request URL: \(AIClient.buildEndpointURL(provider.endpoint))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SecureField("API Key", text: $provider.apiKey)

                    TextField("Model Name", text: $provider.modelName)
                        .help("e.g., gpt-4o, claude-sonnet-4-20250514, gemini-2.0-flash")
                }

                Section("Custom Headers (Optional)") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("One per line, format: Key: Value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $customHeadersText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 50)
                    }
                }

                Section {
                    HStack {
                        Button("Test Connection") {
                            Task { await testConnection() }
                        }
                        .disabled(isTesting || !isFormValid)

                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if let message = testResultMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(testResultIsSuccess ? .green : .red)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Bottom buttons
            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    provider.customHeaders = parseCustomHeaders()
                    onSave(provider)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isFormValid)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 480)
        .onAppear {
            customHeadersText = formatCustomHeaders(provider.customHeaders)
        }
    }

    private var isFormValid: Bool {
        !provider.endpoint.isEmpty && !provider.apiKey.isEmpty && !provider.modelName.isEmpty
    }

    private func parseCustomHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        for line in customHeadersText.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { headers[key] = value }
            }
        }
        return headers
    }

    private func formatCustomHeaders(_ headers: [String: String]) -> String {
        headers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
    }

    private func testConnection() async {
        isTesting = true
        testResultMessage = nil

        let slot = AIModelSlot(
            name: "test",
            endpoint: provider.endpoint,
            apiKey: provider.apiKey,
            modelName: provider.modelName,
            customHeaders: parseCustomHeaders()
        )
        do {
            let ok = try await AIClient.shared.testConnection(config: slot)
            testResultIsSuccess = ok
            testResultMessage = ok ? "Connected" : "Connection Failed: no valid response"
        } catch {
            testResultIsSuccess = false
            testResultMessage = "Connection Failed: \(error.localizedDescription)"
        }

        isTesting = false
    }
}

#Preview {
    AIModelSettingsView()
}
