import SwiftUI

/// Phase-1 Dashboard: current status, today stats, timeline, and app distribution.
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Current Status Card

                currentStatusCard

                // MARK: - Today Stats Grid

                todayStatsGrid

                // MARK: - Today Timeline

                TodayTimelineView(activities: viewModel.todayActivities)

                // MARK: - App Distribution

                AppDistributionView(distribution: viewModel.appDistribution)

                // MARK: - Memory Summary

                memorySummarySection
            }
            .padding()
        }
        .task {
            let dbm = DatabaseManager.shared
            guard let activityDB = dbm.activityDB else { return }
            let store = AppState.shared.activityStore
                ?? ActivityStore(db: activityDB)
            viewModel.startObserving(db: activityDB, store: store, memoryStore: AppState.shared.memoryStore)
        }
    }

    // MARK: - Current Status Card

    @ViewBuilder
    private var currentStatusCard: some View {
        GroupBox {
            if let latest = viewModel.latestActivity {
                HStack(spacing: 12) {
                    Image(systemName: "app.fill")
                        .font(.title)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(latest.appName)
                            .font(.headline)
                        if let summary = latest.contentSummary, !summary.isEmpty {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(latest.timestamp, style: .time)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Image(systemName: "moon.zzz")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No activity records")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        } label: {
            Label("Current Status", systemImage: "desktopcomputer")
                .font(.headline)
        }
    }

    // MARK: - Today Stats Grid

    @ViewBuilder
    private var todayStatsGrid: some View {
        let topApp = viewModel.appDistribution.first?.appName ?? "--"

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            statCard(title: "Captures", value: "\(viewModel.totalCaptures)", icon: "camera.fill", color: .blue)
            statCard(title: "Active Hours", value: String(format: "%.0f", viewModel.activeHours), icon: "clock.fill", color: .green)
            statCard(title: "Focus Score", value: String(format: "%.0f%%", viewModel.focusScore * 100), icon: "brain.head.profile", color: .purple)
            statCard(title: "Top App", value: topApp, icon: "star.fill", color: .orange)
        }
    }

    // MARK: - Memory Summary

    @ViewBuilder
    private var memorySummarySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(viewModel.memoryTotalCount) total")
                    Text("·")
                    Text("\(viewModel.memoryTodayCount) new today")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if viewModel.recentMemoriesByCategory.isEmpty {
                    Text("No memory data")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.recentMemoriesByCategory, id: \.category) { group in
                        Text(memoryCategoryLabel(group.category))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        ForEach(group.memories) { memory in
                            HStack {
                                if memory.pinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Text(memory.content)
                                    .lineLimit(1)
                                Spacer()
                                Text(memory.createdAt.relativeTimeString)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Recent Memories", systemImage: "brain")
                .font(.headline)
        }
    }

    private func memoryCategoryLabel(_ category: String) -> String {
        switch category {
        case "topic": return "Topic"
        case "intent": return "Intent"
        case "habit": return "Habit"
        case "opinion": return "Opinion"
        case "milestone": return "Milestone"
        default: return category
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        GroupBox {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    DashboardView()
        .frame(width: 800, height: 700)
}
