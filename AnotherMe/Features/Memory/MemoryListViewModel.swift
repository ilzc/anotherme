import Foundation
import GRDB

@MainActor
@Observable
final class MemoryListViewModel {

    // MARK: - Published State

    var recentMemories: [Memory] = []
    var consolidatedMemories: [Memory] = []
    var memories: [Memory] = []  // current filtered view (all combined)
    var totalCount: Int = 0
    var todayCount: Int = 0
    var consolidatedCount: Int = 0
    var searchText: String = ""
    var selectedCategory: String? = nil  // nil = all
    var sortOrder: SortOrder = .recency
    var viewMode: ViewMode = .grouped

    enum SortOrder: String, CaseIterable {
        case recency = "Recently Accessed"
        case importance = "Importance"
        case created = "Date Created"
    }

    enum ViewMode: String, CaseIterable {
        case grouped = "Grouped"
        case flat = "Flat"
    }

    // MARK: - Private

    private var memoryStore: MemoryStore?
    private var cancellable: AnyDatabaseCancellable?
    private var allMemories: [Memory] = []

    /// Categories available for filtering.
    static let categories = ["topic", "intent", "habit", "opinion", "milestone"]

    // MARK: - Observation

    /// Begin observing the memories table for live updates.
    func startObserving(store: MemoryStore, db: DatabasePool) {
        self.memoryStore = store

        // Initial load
        fetchFromStore()

        // Live observation
        let observation = DatabaseRegionObservation(tracking: Table("memories"))
        cancellable = observation.start(in: db) { error in
            print("[MemoryListViewModel] observation error: \(error)")
        } onChange: { [weak self] _ in
            Task { @MainActor in
                self?.fetchFromStore()
            }
        }
    }

    /// Re-fetch from database (called on DB changes).
    private func fetchFromStore() {
        guard let store = memoryStore else { return }

        Task.detached { [weak self] in
            do {
                let all = try store.fetchAll(limit: 500)
                let total = try store.totalCount()
                let today = try store.fetchTodayCount()

                await MainActor.run {
                    self?.allMemories = all
                    self?.totalCount = total
                    self?.todayCount = today
                    self?.reapplyFilters()
                }
            } catch {
                print("[MemoryListViewModel] fetch error: \(error)")
            }
        }
    }

    /// Re-apply filters/sort on cached data (called on filter changes).
    func reapplyFilters() {
        var result = allMemories

        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.content.lowercased().contains(query) }
        }

        switch sortOrder {
        case .recency:
            result.sort { $0.lastAccessedAt > $1.lastAccessedAt }
        case .importance:
            result.sort { $0.importance > $1.importance }
        case .created:
            result.sort { $0.createdAt > $1.createdAt }
        }

        memories = result
        recentMemories = result.filter { !$0.isConsolidated }
        consolidatedMemories = result.filter { $0.isConsolidated }
        consolidatedCount = allMemories.filter { $0.isConsolidated }.count
    }

    // MARK: - CRUD Actions

    func deleteMemory(id: String) {
        guard let store = memoryStore else { return }
        try? store.delete(id: id)
    }

    func togglePin(id: String) {
        guard let store = memoryStore else { return }
        try? store.togglePin(id: id)
    }

    func updateImportance(id: String, importance: Double) {
        guard let store = memoryStore else { return }
        try? store.updateImportance(id: id, importance: importance)
    }
}
