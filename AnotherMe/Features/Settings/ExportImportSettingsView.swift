import SwiftUI
import UniformTypeIdentifiers

struct ExportImportSettingsView: View {
    @State private var selectedFormat: ExportFormat = .fullArchive
    @State private var selectedStrategy: ImportStrategy = .merge
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var statusMessage: String?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showOverwriteConfirm = false
    @State private var pendingImportURL: URL?

    var body: some View {
        Form {
            // MARK: - Export
            Section("Export Personality Data") {
                Picker("Export Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Text(formatDescription(selectedFormat))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await performExport() }
                } label: {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting)
            }

            // MARK: - Import
            Section("Import Personality Data") {
                Text("Only Full Archive JSON files are supported")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Conflict Strategy", selection: $selectedStrategy) {
                    ForEach(ImportStrategy.allCases) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }

                Text(strategyDescription(selectedStrategy))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await performImport() }
                } label: {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isImporting)
            }

            // Status
            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Export/Import Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Confirm Overwrite", isPresented: $showOverwriteConfirm) {
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
            }
            Button("Overwrite", role: .destructive) {
                guard let url = pendingImportURL else { return }
                pendingImportURL = nil
                Task { await executeImport(url: url) }
            }
        } message: {
            Text("Overwrite will erase all existing personality data. This cannot be undone. Continue?")
        }
    }

    // MARK: - Export

    @MainActor
    private func performExport() async {
        guard let exporter = buildExporter() else {
            showError(message: "Database not initialized")
            return
        }

        // For AI-generated formats, show save panel first so user can cancel early
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFilename(for: selectedFormat)
        panel.allowedContentTypes = [exportUTType(for: selectedFormat)]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        statusMessage = nil
        defer { isExporting = false }

        do {
            let data = try await exporter.export(format: selectedFormat)
            try data.write(to: url)
            statusMessage = "Export successful: \(url.lastPathComponent)"
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    // MARK: - Import

    @MainActor
    private func performImport() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Destructive strategy needs confirmation
        if selectedStrategy == .overwrite {
            pendingImportURL = url
            showOverwriteConfirm = true
            return
        }

        await executeImport(url: url)
    }

    @MainActor
    private func executeImport(url: URL) async {
        isImporting = true
        statusMessage = nil
        defer { isImporting = false }

        do {
            let data = try Data(contentsOf: url)
            let archive = try PersonalityImporter.validate(data)

            let traitCount = archive.layers.values.reduce(0) { $0 + $1.count }
            let snapshotCount = archive.snapshots?.count ?? 0

            let app = AppState.shared
            guard let l1 = app.layer1Store, let l2 = app.layer2Store,
                  let l3 = app.layer3Store, let l4 = app.layer4Store,
                  let l5 = app.layer5Store else {
                showError(message: "Database not initialized")
                return
            }

            let imported = try PersonalityImporter.importArchive(
                archive,
                strategy: selectedStrategy,
                layer1Store: l1, layer2Store: l2, layer3Store: l3,
                layer4Store: l4, layer5Store: l5,
                snapshotStore: app.snapshotStore
            )

            statusMessage = "Import successful: \(imported) records (archive contains \(traitCount) traits + \(snapshotCount) snapshots)"
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func buildExporter() -> PersonalityExporter? {
        let app = AppState.shared
        guard let l1 = app.layer1Store, let l2 = app.layer2Store,
              let l3 = app.layer3Store, let l4 = app.layer4Store,
              let l5 = app.layer5Store, let snap = app.snapshotStore else {
            return nil
        }
        return PersonalityExporter(
            layer1Store: l1, layer2Store: l2, layer3Store: l3,
            layer4Store: l4, layer5Store: l5, snapshotStore: snap
        )
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }

    private func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .minimal: return "~200 tokens, ideal for AI Custom Instructions (AI-generated)"
        case .card: return "~500 tokens, structured personality card for System Prompt (AI-generated)"
        case .structuredJSON: return "~1-2 KB, structured JSON for Agent platforms/APIs"
        case .fullArchive: return "Full backup with all traits and snapshots, re-importable"
        }
    }

    private func strategyDescription(_ strategy: ImportStrategy) -> String {
        switch strategy {
        case .overwrite: return "Clear existing data and replace entirely with imported data"
        case .merge: return "Keep higher-confidence data, compared dimension by dimension"
        case .missingOnly: return "Only import dimensions not present locally, no overwriting"
        }
    }

    private func exportFilename(for format: ExportFormat) -> String {
        let dateStr = Self.filenameFormatter.string(from: .now)
        switch format {
        case .minimal: return "personality-minimal-\(dateStr).txt"
        case .card: return "personality-card-\(dateStr).md"
        case .structuredJSON: return "personality-\(dateStr).json"
        case .fullArchive: return "personality-archive-\(dateStr).json"
        }
    }

    private func exportUTType(for format: ExportFormat) -> UTType {
        switch format {
        case .minimal: return .plainText
        case .card: return .plainText
        case .structuredJSON, .fullArchive: return .json
        }
    }

    private static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f
    }()
}
