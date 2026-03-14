import SwiftUI

/// Memory management list with search, filter, and CRUD actions.
struct MemoryListView: View {
    @State private var viewModel = MemoryListViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: - Header (search, filters, stats)

            VStack(alignment: .leading, spacing: 12) {
                searchBar
                filterRow
                statsLine
            }
            .padding()

            // MARK: - Memory List

            if viewModel.memories.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    switch viewModel.viewMode {
                    case .grouped:
                        if !viewModel.recentMemories.isEmpty {
                            Section {
                                ForEach(viewModel.recentMemories) { memory in
                                    memoryRowWithActions(memory)
                                }
                            } header: {
                                Label("Recent Memories (\(viewModel.recentMemories.count))", systemImage: "clock")
                            }
                        }
                        if !viewModel.consolidatedMemories.isEmpty {
                            Section {
                                ForEach(viewModel.consolidatedMemories) { memory in
                                    memoryRowWithActions(memory)
                                }
                            } header: {
                                Label("Long-term Summaries (\(viewModel.consolidatedMemories.count))", systemImage: "archivebox")
                            }
                        }
                    case .flat:
                        ForEach(viewModel.memories) { memory in
                            memoryRowWithActions(memory)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .task {
            let dbm = DatabaseManager.shared
            guard let memoryDB = dbm.memoryDB else { return }
            let store = AppState.shared.memoryStore
                ?? MemoryStore(db: memoryDB)
            viewModel.startObserving(store: store, db: memoryDB)
        }
        .onChange(of: viewModel.searchText) {
            viewModel.reapplyFilters()
        }
        .onChange(of: viewModel.selectedCategory) {
            viewModel.reapplyFilters()
        }
        .onChange(of: viewModel.sortOrder) {
            viewModel.reapplyFilters()
        }
        .onChange(of: viewModel.viewMode) {
            viewModel.reapplyFilters()
        }
    }

    // MARK: - Search Bar

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search memories...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Filter Row

    @ViewBuilder
    private var filterRow: some View {
        HStack(spacing: 12) {
            Picker("Category", selection: $viewModel.selectedCategory) {
                Text("All").tag(String?.none)
                ForEach(MemoryListViewModel.categories, id: \.self) { cat in
                    Text(categoryLabel(cat)).tag(Optional(cat))
                }
            }
            .pickerStyle(.menu)

            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(MemoryListViewModel.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)

            Spacer()
        }
    }

    // MARK: - Stats Line

    @ViewBuilder
    private var statsLine: some View {
        HStack {
            Text("\(viewModel.totalCount) total · \(viewModel.todayCount) new today")
                .font(.caption)
                .foregroundStyle(.secondary)
            if viewModel.consolidatedCount > 0 {
                Text("· \(viewModel.consolidatedCount) summaries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $viewModel.viewMode) {
                ForEach(MemoryListViewModel.ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }

    // MARK: - Memory Row (with actions)

    @ViewBuilder
    private func memoryRowWithActions(_ memory: Memory) -> some View {
        memoryRow(memory)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    viewModel.deleteMemory(id: memory.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                Button {
                    viewModel.togglePin(id: memory.id)
                } label: {
                    Label(memory.pinned ? "Unpin" : "Pin",
                          systemImage: memory.pinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
            .contextMenu {
                Button {
                    viewModel.togglePin(id: memory.id)
                } label: {
                    Label(memory.pinned ? "Unpin" : "Pin",
                          systemImage: memory.pinned ? "pin.slash" : "pin")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(memory.content, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive) {
                    viewModel.deleteMemory(id: memory.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    private func memoryRow(_ memory: Memory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                if memory.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(memory.content)
                    .font(.body)
                    .lineLimit(3)
                Spacer()
            }

            HStack(spacing: 8) {
                categoryTag(memory.category)

                if memory.isConsolidated {
                    Text("Summary")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.indigo.opacity(0.15), in: Capsule())
                        .foregroundStyle(.indigo)
                } else {
                    Text(memory.sourceType)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(memory.lastAccessedAt.relativeTimeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Text(String(format: "%.0f%%", memory.importance * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No memories yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Memories are automatically extracted from conversations and activity analysis.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func categoryLabel(_ category: String) -> String {
        switch category {
        case "topic": return "Topic"
        case "intent": return "Intent"
        case "habit": return "Habit"
        case "opinion": return "Opinion"
        case "milestone": return "Milestone"
        default: return category
        }
    }

    @ViewBuilder
    private func categoryTag(_ category: String) -> some View {
        Text(categoryLabel(category))
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(categoryColor(category).opacity(0.15), in: Capsule())
            .foregroundStyle(categoryColor(category))
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "topic": return .blue
        case "intent": return .purple
        case "habit": return .green
        case "opinion": return .orange
        case "milestone": return .red
        default: return .secondary
        }
    }
}

#Preview {
    MemoryListView()
        .frame(width: 600, height: 700)
}
