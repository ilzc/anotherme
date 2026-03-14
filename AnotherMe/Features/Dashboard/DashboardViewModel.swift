import Foundation
import GRDB

/// Dashboard data logic: observes activity_logs for live updates and computes
/// today's statistics (captures, active hours, focus score, distributions).
@Observable
final class DashboardViewModel {

    // MARK: - Published State

    var todayActivities: [ActivityRecord] = []
    var appDistribution: [(appName: String, count: Int)] = []
    var categoryDistribution: [(category: String, count: Int)] = []
    var latestActivity: ActivityRecord?
    var totalCaptures: Int = 0
    var activeHours: Double = 0
    var focusScore: Double = 0

    // Memory summary
    var memoryTotalCount: Int = 0
    var memoryTodayCount: Int = 0
    var recentMemoriesByCategory: [(category: String, memories: [Memory])] = []

    // MARK: - Private

    private var activityStore: ActivityStore?
    private var memoryStore: MemoryStore?
    private var cancellable: AnyDatabaseCancellable?
    private var memoryCancellable: AnyDatabaseCancellable?

    // MARK: - Observation

    /// Begin observing the activity_logs table for changes.
    /// Call once from the view's `.task` modifier.
    func startObserving(db: DatabasePool, store: ActivityStore, memoryStore: MemoryStore? = nil) {
        self.activityStore = store
        self.memoryStore = memoryStore

        // Initial load
        reload()
        reloadMemories()

        // Live observation via GRDB DatabaseRegionObservation
        let observation = DatabaseRegionObservation(tracking: ActivityRecord.all())
        cancellable = observation.start(in: db) { error in
            print("[DashboardViewModel] observation error: \(error)")
        } onChange: { [weak self] _ in
            Task { @MainActor in
                self?.reload()
            }
        }

        // Observe memory database for changes
        if let memoryDB = DatabaseManager.shared.memoryDB {
            let memoryObservation = DatabaseRegionObservation(tracking: Memory.all())
            memoryCancellable = memoryObservation.start(in: memoryDB) { error in
                print("[DashboardViewModel] memory observation error: \(error)")
            } onChange: { [weak self] _ in
                Task { @MainActor in
                    self?.reloadMemories()
                }
            }
        }
    }

    /// Manually refresh all data from the store.
    func reload() {
        guard let store = activityStore else { return }

        Task.detached { [weak self] in
            do {
                let activities = try store.fetchToday()
                let appDist = try store.fetchTodayAppDistribution()
                let catDist = try store.fetchTodayCategoryDistribution()
                let activeHours = Self.calculateActiveHours(from: activities)
                let focusScore = Self.calculateFocusScore(from: activities)

                await MainActor.run {
                    self?.todayActivities = activities
                    self?.appDistribution = appDist
                    self?.categoryDistribution = catDist
                    self?.latestActivity = activities.last
                    self?.totalCaptures = activities.count
                    self?.activeHours = activeHours
                    self?.focusScore = focusScore
                }
            } catch {
                print("[DashboardViewModel] reload error: \(error)")
            }
        }
    }

    /// Reload memory summary data from the memory store.
    func reloadMemories() {
        guard let store = memoryStore else { return }

        Task.detached { [weak self] in
            let totalCount = (try? store.totalCount()) ?? 0
            let todayCount = (try? store.fetchTodayCount()) ?? 0

            // Fetch recent memories, filter by importance, group by category
            let allRecent = (try? store.fetchAll(limit: 20)) ?? []
            let filtered = allRecent.filter { $0.importance > 0.3 }

            // Group by category
            var grouped: [String: [Memory]] = [:]
            for memory in filtered {
                grouped[memory.category, default: []].append(memory)
            }

            // Take top 3 per category, sort groups by most recent memory
            let categoryGroups: [(category: String, memories: [Memory])] = grouped
                .map { (category: $0.key, memories: Array($0.value.prefix(3))) }
                .sorted { groupA, groupB in
                    let latestA = groupA.memories.map(\.createdAt).max() ?? .distantPast
                    let latestB = groupB.memories.map(\.createdAt).max() ?? .distantPast
                    return latestA > latestB
                }

            await MainActor.run {
                self?.memoryTotalCount = totalCount
                self?.memoryTodayCount = todayCount
                self?.recentMemoriesByCategory = categoryGroups
            }
        }
    }

    // MARK: - Calculations

    /// Count distinct calendar hours that contain at least one activity record.
    static func calculateActiveHours(from activities: [ActivityRecord]) -> Double {
        guard !activities.isEmpty else { return 0 }
        let calendar = Calendar.current
        var activeHourSet = Set<Int>()
        for activity in activities {
            let hour = calendar.component(.hour, from: activity.timestamp)
            activeHourSet.insert(hour)
        }
        return Double(activeHourSet.count)
    }

    /// Hourly focus score: fewer app switches per hour = higher score.
    /// Score is 0.0 ... 1.0, averaged across active hours.
    ///
    /// Per hour: switches = number of times the app name changes between
    /// consecutive records.  score_h = max(0, 1 - switches / 10).
    /// Overall score = average of per-hour scores.
    static func calculateFocusScore(from activities: [ActivityRecord]) -> Double {
        guard activities.count >= 2 else {
            return activities.isEmpty ? 0 : 1.0
        }

        let calendar = Calendar.current

        // Group activities by hour
        var hourlyActivities: [Int: [ActivityRecord]] = [:]
        for activity in activities {
            let hour = calendar.component(.hour, from: activity.timestamp)
            hourlyActivities[hour, default: []].append(activity)
        }

        guard !hourlyActivities.isEmpty else { return 0 }

        var totalScore: Double = 0
        for (_, records) in hourlyActivities {
            guard records.count >= 2 else {
                totalScore += 1.0
                continue
            }
            var switches = 0
            for i in 1..<records.count {
                if records[i].appName != records[i - 1].appName {
                    switches += 1
                }
            }
            let hourScore = max(0.0, 1.0 - Double(switches) / 10.0)
            totalScore += hourScore
        }

        return totalScore / Double(hourlyActivities.count)
    }
}
