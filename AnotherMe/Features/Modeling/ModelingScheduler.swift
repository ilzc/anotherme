import Foundation

@MainActor
@Observable
final class ModelingScheduler {
    struct Config {
        var dailyAnalysisHour: Int = 23
        var weeklyAnalysisDay: Int = 1  // 1=Sunday
        var thresholdRecordCount: Int = 200
        var enabled: Bool = true
    }

    enum TriggerReason: String, Sendable {
        case daily, weekly, threshold, manual
    }

    private(set) var isRunning = false
    private(set) var lastRunDate: Date?
    private(set) var pendingRecordCount: Int = 0

    var onTrigger: ((TriggerReason) -> Void)?

    private var dailyTimer: Task<Void, Never>?
    private var thresholdCheckTimer: Task<Void, Never>?
    private var config: Config = Config()

    func start(config: Config, activityStore: ActivityStore) {
        guard !isRunning else { return }
        self.config = config
        guard config.enabled else { return }
        isRunning = true
        startDailyTimer()
        startThresholdCheck(activityStore: activityStore)
    }

    func stop() {
        isRunning = false
        dailyTimer?.cancel()
        dailyTimer = nil
        thresholdCheckTimer?.cancel()
        thresholdCheckTimer = nil
    }

    func triggerManually() {
        onTrigger?(.manual)
    }

    private func startDailyTimer() {
        dailyTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                let calendar = Calendar.current
                var target = calendar.date(bySettingHour: self.config.dailyAnalysisHour, minute: 0, second: 0, of: now)!
                if target <= now {
                    target = calendar.date(byAdding: .day, value: 1, to: target)!
                }
                let delay = target.timeIntervalSince(now)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }

                // Check if it's also the weekly day
                let weekday = calendar.component(.weekday, from: Date())
                if weekday == self.config.weeklyAnalysisDay {
                    self.lastRunDate = Date()
                    self.onTrigger?(.weekly)
                } else {
                    self.lastRunDate = Date()
                    self.onTrigger?(.daily)
                }
            }
        }
    }

    /// Minimum interval between threshold-triggered analyses (60 minutes).
    private let thresholdCooldown: TimeInterval = 3600

    private func startThresholdCheck(activityStore: ActivityStore) {
        thresholdCheckTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))  // Check every 5 minutes
                guard !Task.isCancelled, let self else { return }

                // Cooldown: skip if analysis ran recently
                if let last = self.lastRunDate,
                   Date().timeIntervalSince(last) < self.thresholdCooldown {
                    continue
                }

                do {
                    let count = try self.countUnanalyzed(activityStore: activityStore)
                    self.pendingRecordCount = count
                    if count >= self.config.thresholdRecordCount {
                        self.lastRunDate = Date()
                        self.onTrigger?(.threshold)
                    }
                } catch {
                    // Silently continue
                }
            }
        }
    }

    private func countUnanalyzed(activityStore: ActivityStore) throws -> Int {
        let records = try activityStore.fetchUnanalyzed(limit: config.thresholdRecordCount + 1)
        return records.count
    }
}
