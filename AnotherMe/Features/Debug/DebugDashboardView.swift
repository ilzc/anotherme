import SwiftUI

struct DebugDashboardView: View {
    @State private var selectedTab: DebugTab = .liveRequests
    @State private var selectedRequest: TrackedRequest?
    @State private var selectedEntry: DebugLogEntry?
    @State private var trackedRequests: [TrackedRequest] = []
    @State private var logEntries: [DebugLogEntry] = []
    @State private var categoryFilter: CategoryFilter = .all

    /// Timer that fires every 1s to refresh live data from DebugLogger.
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private enum DebugTab: String, CaseIterable {
        case liveRequests = "Request Tracking"
        case logBrowser = "Log Browser"
        case dataManagement = "Data Management"
    }

    private enum CategoryFilter: String, CaseIterable {
        case all = "All"
        case capture = "Capture"
        case llm = "LLM Call"
        case stored = "Stored"

        var category: DebugLogEntry.Category? {
            switch self {
            case .all: nil
            case .capture: .capture
            case .llm: .llm
            case .stored: .stored
            }
        }
    }

    var body: some View {
        if !DebugLogger.shared.isEnabled {
            disabledView
        } else {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(DebugTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                if selectedTab == .dataManagement {
                    DataManagementView()
                } else {
                    HSplitView {
                        sidebarContent
                            .frame(minWidth: 300, idealWidth: 360, maxWidth: 450)
                        detailView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .onAppear {
                trackedRequests = DebugLogger.shared.trackedRequests
                logEntries = DebugLogger.shared.loadEntries()
            }
            .onReceive(refreshTimer) { _ in
                trackedRequests = DebugLogger.shared.trackedRequests
                if selectedTab == .logBrowser {
                    logEntries = DebugLogger.shared.loadEntries()
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            switch selectedTab {
            case .liveRequests:
                liveRequestsList
            case .logBrowser:
                logBrowserList
            case .dataManagement:
                EmptyView()
            }
        }
    }

    // MARK: - Live Requests List

    private var liveRequestsList: some View {
        Group {
            HStack {
                Text("\(trackedRequests.count) requests")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    DebugLogger.shared.trackedRequests.removeAll()
                    trackedRequests = []
                    selectedRequest = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear list")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if trackedRequests.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Waiting for requests...")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(trackedRequests, selection: $selectedRequest) { req in
                    RequestRow(request: req)
                        .tag(req)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Log Browser List

    private var logBrowserList: some View {
        let filtered: [DebugLogEntry] = {
            guard let cat = categoryFilter.category else { return logEntries }
            return logEntries.filter { $0.category == cat }
        }()
        return Group {
            HStack {
                Picker("", selection: $categoryFilter) {
                    ForEach(CategoryFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    logEntries = DebugLogger.shared.loadEntries()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            if filtered.isEmpty {
                Spacer()
                Text("No debug records")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered, selection: $selectedEntry) { entry in
                    LogEntryRow(entry: entry)
                        .tag(entry)
                }
                .listStyle(.inset)
            }
        }
        // logEntries are refreshed by the timer in the main body
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .liveRequests:
            if let req = selectedRequest {
                RequestDetailView(request: req)
            } else {
                Text("Select a request to view details")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .logBrowser:
            if let entry = selectedEntry {
                LogEntryDetailView(entry: entry)
            } else {
                Text("Select a record to view details")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .dataManagement:
            EmptyView()
        }
    }

    private var disabledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "ladybug")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Developer Mode Not Enabled")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Go to Settings > Developer to enable Developer Mode")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Request Row

private struct RequestRow: View {
    let request: TrackedRequest

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(request.function)
                        .font(.callout)
                        .fontWeight(.medium)
                    Spacer()
                    statusBadge
                }
                HStack(spacing: 8) {
                    Text(request.model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let ms = request.durationMs {
                        Text("\(ms) ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let usage = request.tokenUsage {
                        Text("\(usage.total) tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(request.startTime, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch request.status {
        case .pending:
            Circle().fill(.orange)
        case .completed:
            Circle().fill(.green)
        case .error:
            Circle().fill(.red)
        }
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = switch request.status {
        case .pending: ("Pending", .orange)
        case .completed: ("Completed", .green)
        case .error: ("Error", .red)
        }
        return Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Request Detail View

private struct RequestDetailView: View {
    let request: TrackedRequest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.function)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(request.startTime, format: .dateTime.year().month().day().hour().minute().second())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusView
                }

                GroupBox("Basic Info") {
                    VStack(alignment: .leading, spacing: 6) {
                        labeledField("Function", value: request.function)
                        labeledField("Model", value: request.model)
                        labeledField("Endpoint", value: request.endpoint)
                        if let ms = request.durationMs {
                            labeledField("Duration", value: "\(ms) ms")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = request.errorMessage {
                    GroupBox("Error") {
                        Text(error)
                            .font(.callout.monospaced())
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !request.requestMessages.isEmpty {
                    GroupBox("Request Messages") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(request.requestMessages.enumerated()), id: \.offset) { _, msg in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(msg.role)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                    Text(msg.preview)
                                        .font(.callout.monospaced())
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Divider()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let preview = request.responsePreview {
                    GroupBox("Response") {
                        Text(preview)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let usage = request.tokenUsage {
                    GroupBox("Token Usage") {
                        VStack(alignment: .leading, spacing: 4) {
                            labeledField("Input", value: "\(usage.prompt)")
                            labeledField("Output", value: "\(usage.completion)")
                            labeledField("Total", value: "\(usage.total)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var statusView: some View {
        switch request.status {
        case .pending:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Pending")
                    .foregroundStyle(.orange)
            }
        case .completed:
            Label("Completed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Label("Error", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func labeledField(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: DebugLogEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.functionName)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(iconColor.opacity(0.15))
                        .foregroundStyle(iconColor)
                        .clipShape(Capsule())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch entry.category {
        case .capture: "photo"
        case .llm: "arrow.up.arrow.down"
        case .stored: "internaldrive"
        }
    }

    private var iconColor: Color {
        switch entry.category {
        case .capture: .blue
        case .llm: .orange
        case .stored: .green
        }
    }
}

// MARK: - Log Entry Detail View

private struct LogEntryDetailView: View {
    let entry: DebugLogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.functionName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(entry.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(entry.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch entry.category {
                case .capture:
                    captureContent
                case .llm:
                    llmContent
                case .stored:
                    storedContent
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var captureContent: some View {
        if let data = DebugLogger.shared.loadScreenshotData(entry: entry),
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)
        } else {
            Text("Unable to load screenshot")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var llmContent: some View {
        if let detail = DebugLogger.shared.loadLLMDetail(entry: entry) {
            let req = detail["request"] as? [String: Any]
            let resp = detail["response"] as? [String: Any]

            GroupBox("Basic Info") {
                VStack(alignment: .leading, spacing: 6) {
                    if let m = detail["model"] as? String { field("Model", m) }
                    if let e = detail["endpoint"] as? String { field("Endpoint", e) }
                    if let d = detail["duration_ms"] as? Int { field("Duration", "\(d) ms") }
                    if let t = req?["temperature"] { field("Temperature", "\(t)") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = detail["error"] as? String {
                GroupBox("Error") {
                    Text(error)
                        .font(.callout.monospaced())
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let messages = req?["messages"] as? [[String: Any]] {
                GroupBox("Request Messages") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(msg["role"] as? String ?? "")
                                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                                if let arr = msg["content"] as? [[String: Any]] {
                                    ForEach(Array(arr.enumerated()), id: \.offset) { _, item in
                                        if let text = item["text"] as? String {
                                            Text(String(text.prefix(2000)))
                                                .font(.callout.monospaced())
                                                .textSelection(.enabled)
                                                .fixedSize(horizontal: false, vertical: true)
                                        } else if item["type"] as? String == "image_url" {
                                            Label("(Image omitted)", systemImage: "photo")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let choices = resp?["choices"] as? [[String: Any]] {
                GroupBox("Response") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(choices.enumerated()), id: \.offset) { _, c in
                            if let text = c["content"] as? String {
                                Text(text).font(.callout.monospaced()).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let usage = resp?["usage"] as? [String: Any] {
                GroupBox("Token Usage") {
                    VStack(alignment: .leading, spacing: 4) {
                        if let v = usage["prompt_tokens"] { field("Input", "\(v)") }
                        if let v = usage["completion_tokens"] { field("Output", "\(v)") }
                        if let v = usage["total_tokens"] { field("Total", "\(v)") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            Text("Unable to load details").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var storedContent: some View {
        if let detail = DebugLogger.shared.loadStoredDetail(entry: entry) {
            GroupBox("Data") {
                Text(prettyPrint(detail))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Unable to load details").foregroundStyle(.secondary)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func prettyPrint(_ value: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }
}

// MARK: - Data Management View

private struct DataManagementView: View {
    @State private var statusMessage: String?
    @State private var showResetAllConfirm = false
    @State private var dataCounts: DataCounts = .empty
    private var analysisState: ForceAnalysisState { ForceAnalysisState.shared }
    @State private var elapsedTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var elapsedDisplay: TimeInterval = 0

    private let appState = AppState.shared

    @State private var isConsolidating = false
    @State private var consolidationResult: String?

    struct DataCounts {
        var activity: Int = 0
        var layer1: Int = 0
        var layer2: Int = 0
        var layer3: Int = 0
        var layer4Traits: Int = 0
        var layer4Samples: Int = 0
        var layer5: Int = 0
        var snapshots: Int = 0
        var insights: Int = 0
        var memoryTotal: Int = 0
        var memoryConsolidated: Int = 0

        static let empty = DataCounts()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Data Management")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Delete capture and analysis data, useful for re-analysis after modifying prompts or logic")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showResetAllConfirm = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash.fill")
                    }
                    .confirmationDialog("Confirm reset all data?", isPresented: $showResetAllConfirm) {
                        Button("Reset All", role: .destructive) { resetAll() }
                    } message: {
                        Text("This will delete all capture records and analysis results. This action cannot be undone.")
                    }
                }

                if let msg = statusMessage {
                    Text(msg)
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Raw Data
                GroupBox("Capture Data") {
                    VStack(spacing: 0) {
                        dataRow(
                            title: "Activity Records",
                            subtitle: "Raw records from screenshot analysis",
                            count: dataCounts.activity,
                            onDelete: { deleteData { try appState.activityStore?.deleteAll() } }
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Analysis Results
                GroupBox("Analysis Results (from Modeling)") {
                    VStack(spacing: 0) {
                        dataRow(
                            title: "Layer 1 - Behavioral Rhythm",
                            subtitle: "Daily rhythm + rhythm traits",
                            count: dataCounts.layer1,
                            onDelete: { deleteData { try appState.layer1Store?.deleteAll() } }
                        )
                        Divider().padding(.vertical, 4)
                        dataRow(
                            title: "Layer 2 - Knowledge Graph",
                            subtitle: "Knowledge nodes + edges + traits",
                            count: dataCounts.layer2,
                            onDelete: { deleteData { try appState.layer2Store?.deleteAll() } }
                        )
                        Divider().padding(.vertical, 4)
                        dataRow(
                            title: "Layer 3 - Cognitive Style",
                            subtitle: "Cognitive traits + problem-solving sequences",
                            count: dataCounts.layer3,
                            onDelete: { deleteData { try appState.layer3Store?.deleteAll() } }
                        )
                        Divider().padding(.vertical, 4)
                        dataRow(
                            title: "Layer 4 - Expression Style",
                            subtitle: "Expression traits: \(dataCounts.layer4Traits) + writing samples: \(dataCounts.layer4Samples)",
                            count: dataCounts.layer4Traits + dataCounts.layer4Samples,
                            onDelete: { deleteData { try appState.layer4Store?.deleteAll() } }
                        )
                        Divider().padding(.vertical, 4)
                        dataRow(
                            title: "Layer 5 - Values",
                            subtitle: "Value traits",
                            count: dataCounts.layer5,
                            onDelete: { deleteData { try appState.layer5Store?.deleteAll() } }
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Other Data") {
                    VStack(spacing: 0) {
                        dataRow(
                            title: "Personality Snapshots",
                            subtitle: "Periodically generated personality profile summaries",
                            count: dataCounts.snapshots,
                            onDelete: { deleteData { try appState.snapshotStore?.deleteAll() } }
                        )
                        Divider().padding(.vertical, 4)
                        dataRow(
                            title: "Insights",
                            subtitle: "System-generated insight records",
                            count: dataCounts.insights,
                            onDelete: { deleteData { try appState.insightStore?.deleteAll() } }
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Memory consolidation
                GroupBox("Memory Consolidation") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total memories: \(dataCounts.memoryTotal) (consolidated: \(dataCounts.memoryConsolidated))")
                                    .font(.callout)
                                Text("Skip the 14-day waiting period and immediately run AI consolidation on low-importance memories")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                forceConsolidate()
                            } label: {
                                if isConsolidating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Consolidate Now")
                                }
                            }
                            .disabled(isConsolidating || dataCounts.memoryTotal == 0)
                        }

                        if let result = consolidationResult {
                            Text(result)
                                .font(.caption)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.green.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Quick actions
                GroupBox("Quick Actions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Clear Analysis Only (keep capture data)") {
                            deleteAnalysisOnly()
                        }
                        .help("Keep raw activity records, only delete Layer 1-5 + snapshots + insights, then re-model")

                        Button("Reset Analysis Flags on Activity Records") {
                            resetAnalyzedFlags()
                        }
                        .help("Mark all activity records as unanalyzed; next modeling run will reprocess them")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Force analysis with progress
                forceAnalysisSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { refreshCounts() }
        .onReceive(elapsedTimer) { _ in
            if analysisState.isRunning {
                elapsedDisplay = analysisState.elapsedTime
            }
        }
    }

    // MARK: - Force Analysis Section

    private var forceAnalysisSection: some View {
        GroupBox("Force Analysis (using all activity records)") {
            VStack(alignment: .leading, spacing: 12) {
                // Layer buttons
                HStack(spacing: 8) {
                    forceRunButton(label: "All", layer: 0)
                    Divider().frame(height: 20)
                    forceRunButton(label: "L1 Rhythm", layer: 1)
                    forceRunButton(label: "L2 Knowledge", layer: 2)
                    forceRunButton(label: "L3 Cognitive", layer: 3)
                    forceRunButton(label: "L4 Expression", layer: 4)
                    forceRunButton(label: "L5 Values", layer: 5)

                    Spacer()

                    if analysisState.recordCount > 0 {
                        Text("\(analysisState.recordCount) records")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Progress panel (shown when running or has results)
                if analysisState.isRunning || !analysisState.layerStatuses.isEmpty {
                    progressPanel
                }

                if !analysisState.isRunning && analysisState.layerStatuses.isEmpty {
                    Text("Ignores minimum data requirements and throttling. Re-generates analysis results using all activity records. All layers use AI analysis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Progress Panel

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Overall progress bar + elapsed time + cancel
            if analysisState.isRunning {
                HStack(spacing: 10) {
                    ProgressView(value: analysisState.overallProgress)
                        .frame(maxWidth: .infinity)

                    Text("\(analysisState.completedLayers.count)/\(analysisState.targetLayers.count) layers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)

                    Text(formatElapsed(elapsedDisplay))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)

                    Button("Cancel") {
                        analysisState.cancel()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .font(.caption)
                }
            }

            // Per-layer status
            VStack(alignment: .leading, spacing: 4) {
                ForEach(analysisState.targetLayers, id: \.self) { layer in
                    layerStatusRow(layer: layer)
                }
            }

            // Log view
            if !analysisState.logs.isEmpty {
                Divider()
                analysisLogView
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func layerStatusRow(layer: Int) -> some View {
        let status = analysisState.layerStatuses[layer] ?? .pending

        return HStack(spacing: 8) {
            layerStatusIcon(status)
                .frame(width: 16, height: 16)

            Text(layerName(layer))
                .font(.callout)
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)

            switch status {
            case .pending:
                Text("Waiting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .running(let step):
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            case .completed(let duration):
                Text(String(format: "%.1fs", duration))
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed(let error):
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            case .skipped(let reason):
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func layerStatusIcon(_ status: ForceAnalysisState.LayerStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption2)
        case .running:
            Image(systemName: "circle.fill")
                .foregroundStyle(.orange)
                .font(.caption2)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption2)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption2)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption2)
        }
    }

    private var analysisLogView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(analysisState.logs) { log in
                        HStack(alignment: .top, spacing: 6) {
                            Text(log.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .frame(width: 60, alignment: .leading)

                            Text(log.layer > 0 ? "L\(log.layer)" : "  ")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            logLevelIcon(log.level)
                                .frame(width: 10)

                            Text(log.message)
                                .font(.caption)
                                .foregroundStyle(logColor(log.level))
                                .lineLimit(2)
                        }
                        .id(log.id)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 180)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onChange(of: analysisState.logs.count) { _, _ in
                if let last = analysisState.logs.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func logLevelIcon(_ level: ForceAnalysisState.LogEntry.Level) -> some View {
        switch level {
        case .info:
            Text(" ")
                .font(.caption2)
        case .success:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
        case .error:
            Image(systemName: "xmark")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private func logColor(_ level: ForceAnalysisState.LogEntry.Level) -> Color {
        switch level {
        case .info: .primary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private func layerName(_ layer: Int) -> String {
        switch layer {
        case 1: "L1 Behavioral Rhythm"
        case 2: "L2 Knowledge Graph"
        case 3: "L3 Cognitive Style"
        case 4: "L4 Expression Style"
        case 5: "L5 Values"
        default: "Layer \(layer)"
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Row

    private func dataRow(title: String, subtitle: String, count: Int, onDelete: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(count == 0)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Force Run

    private func forceRunButton(label: String, layer: Int) -> some View {
        Button {
            forceRunLayer(layer)
        } label: {
            Text(label)
        }
        .disabled(analysisState.isRunning || dataCounts.activity == 0)
    }

    private func forceRunLayer(_ layer: Int) {
        guard let engine = appState.modelingEngine else {
            showStatus("Modeling engine not initialized")
            return
        }

        let layers = layer == 0 ? [1, 2, 3, 4, 5] : [layer]
        analysisState.reset(layers: layers)

        let task = Task {
            do {
                try await engine.forceRunLayer(layer, state: analysisState)
                await MainActor.run {
                    showStatus("Analysis complete")
                    refreshCounts()
                }
            } catch {
                await MainActor.run {
                    if !analysisState.isRunning {
                        // Already handled (cancelled or finished)
                    } else {
                        analysisState.finish()
                    }
                    showStatus("Analysis failed: \(error.localizedDescription)")
                }
            }
        }
        analysisState.setTask(task)
    }

    // MARK: - Actions

    private func deleteData(_ action: () throws -> Void) {
        do {
            try action()
            showStatus("Deleted successfully")
            refreshCounts()
        } catch {
            showStatus("Delete failed: \(error.localizedDescription)")
        }
    }

    private func resetAll() {
        do {
            try appState.activityStore?.deleteAll()
            try appState.layer1Store?.deleteAll()
            try appState.layer2Store?.deleteAll()
            try appState.layer3Store?.deleteAll()
            try appState.layer4Store?.deleteAll()
            try appState.layer5Store?.deleteAll()
            try appState.snapshotStore?.deleteAll()
            try appState.insightStore?.deleteAll()
            showStatus("All data has been reset")
            refreshCounts()
        } catch {
            showStatus("Reset failed: \(error.localizedDescription)")
        }
    }

    private func deleteAnalysisOnly() {
        do {
            try appState.layer1Store?.deleteAll()
            try appState.layer2Store?.deleteAll()
            try appState.layer3Store?.deleteAll()
            try appState.layer4Store?.deleteAll()
            try appState.layer5Store?.deleteAll()
            try appState.snapshotStore?.deleteAll()
            try appState.insightStore?.deleteAll()
            showStatus("Analysis results cleared, capture data preserved")
            refreshCounts()
        } catch {
            showStatus("Clear failed: \(error.localizedDescription)")
        }
    }

    private func resetAnalyzedFlags() {
        do {
            try appState.activityStore?.resetAnalyzedFlags()
            showStatus("Analysis flags reset; all records will be reprocessed on next modeling run")
        } catch {
            showStatus("Reset failed: \(error.localizedDescription)")
        }
    }

    private func forceConsolidate() {
        guard let consolidator = appState.memoryConsolidator else {
            consolidationResult = "Memory consolidator not initialized"
            return
        }
        isConsolidating = true
        consolidationResult = nil
        Task {
            do {
                let (consolidated, originals) = try await consolidator.forceConsolidate()
                await MainActor.run {
                    isConsolidating = false
                    if consolidated == 0 {
                        consolidationResult = "No memories to consolidate (requires at least 3 low-importance, non-pinned memories)"
                    } else {
                        consolidationResult = "Done: \(originals) original memories -> \(consolidated) summaries"
                    }
                    refreshCounts()
                }
            } catch {
                await MainActor.run {
                    isConsolidating = false
                    consolidationResult = "Consolidation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    private func refreshCounts() {
        var counts = DataCounts()
        counts.activity = (try? appState.activityStore?.totalCount()) ?? 0
        counts.layer1 = (try? appState.layer1Store?.rhythmCount()) ?? 0
            + ((try? appState.layer1Store?.fetchTraits().count) ?? 0)
        counts.layer2 = (try? appState.layer2Store?.nodeCount()) ?? 0
            + ((try? appState.layer2Store?.fetchTraits().count) ?? 0)
        counts.layer3 = (try? appState.layer3Store?.sequenceCount()) ?? 0
            + ((try? appState.layer3Store?.fetchTraits().count) ?? 0)
        counts.layer4Traits = (try? appState.layer4Store?.fetchTraits().count) ?? 0
        counts.layer4Samples = (try? appState.layer4Store?.sampleCount()) ?? 0
        counts.layer5 = (try? appState.layer5Store?.traitCount()) ?? 0
        counts.snapshots = (try? appState.snapshotStore?.snapshotCount()) ?? 0
        counts.insights = (try? appState.insightStore?.insightCount()) ?? 0
        counts.memoryTotal = (try? appState.memoryStore?.totalCount()) ?? 0
        counts.memoryConsolidated = (try? appState.memoryStore?.consolidatedCount()) ?? 0
        dataCounts = counts
    }
}

#Preview {
    DebugDashboardView()
        .frame(width: 900, height: 600)
}
