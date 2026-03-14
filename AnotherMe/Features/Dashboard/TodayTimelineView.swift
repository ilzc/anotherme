import SwiftUI
import Charts

/// Horizontal Gantt-style timeline of today's activities using Swift Charts.
/// Each activity is rendered as a colored RectangleMark; idle gaps are shown in gray.
struct TodayTimelineView: View {
    let activities: [ActivityRecord]

    var body: some View {
        GroupBox {
            if activities.isEmpty {
                placeholder
            } else {
                timelineChart
            }
        } label: {
            Label("Today's Activity Timeline", systemImage: "timeline.selection")
                .font(.headline)
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var timelineChart: some View {
        let segments = buildSegments()

        Chart(segments) { segment in
            RectangleMark(
                xStart: .value("Start", segment.start),
                xEnd: .value("End", segment.end),
                y: .value("Activity", "Today")
            )
            .foregroundStyle(segment.color)
            .cornerRadius(2)
            .opacity(segment.isIdle ? 0.25 : 0.85)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 1)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)))
            }
        }
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        // Tooltip handled via chartOverlay if needed
                    }
            }
        }
        .frame(height: 60)
        .padding(.vertical, 4)
    }

    // MARK: - Placeholder

    private var placeholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No activity data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
    }

    // MARK: - Segment Building

    private func buildSegments() -> [TimelineSegment] {
        guard !activities.isEmpty else { return [] }

        var segments: [TimelineSegment] = []
        let defaultDuration: TimeInterval = 300   // 5 minutes default for last activity
        let maxDuration: TimeInterval = 900       // cap individual segment at 15 minutes
        let idleThreshold: TimeInterval = 600     // gap > 10 min counts as idle

        // End of today (start of next day) for clamping midnight boundaries
        let calendar = Calendar.current
        let endOfDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: activities[0].timestamp)!)

        for i in 0..<activities.count {
            let activity = activities[i]
            let start = activity.timestamp

            // Determine end: either gap to next activity (capped) or default duration for last
            var end: Date
            if i + 1 < activities.count {
                let nextStart = activities[i + 1].timestamp
                let gap = nextStart.timeIntervalSince(start)

                if gap <= idleThreshold {
                    end = nextStart
                } else {
                    // Activity ends after capped estimated duration; idle gap inserted after
                    let estimatedDuration = min(gap, maxDuration)
                    end = start.addingTimeInterval(estimatedDuration)

                    // Clamp to end of day
                    end = min(end, endOfDay)

                    // Insert idle segment for the gap
                    let idleStart = end
                    let idleEnd = min(nextStart, endOfDay)
                    if idleEnd > idleStart {
                        segments.append(TimelineSegment(
                            id: "idle-\(i)",
                            start: idleStart,
                            end: idleEnd,
                            appName: "Idle",
                            summary: nil,
                            isIdle: true,
                            color: .gray
                        ))
                    }
                }
            } else {
                // Last activity: show default duration
                end = start.addingTimeInterval(defaultDuration)
            }

            // Clamp segment end to end of day
            end = min(end, endOfDay)

            segments.append(TimelineSegment(
                id: activity.id.uuidString,
                start: start,
                end: end,
                appName: activity.appName,
                summary: activity.contentSummary,
                isIdle: false,
                color: Self.colorForApp(activity.appName)
            ))
        }

        return segments
    }

    /// Deterministic color based on app name hash.
    static func colorForApp(_ appName: String) -> Color {
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .pink,
            .cyan, .indigo, .mint, .teal, .red,
            .yellow, .brown
        ]
        let hash = abs(appName.hashValue)
        return palette[hash % palette.count]
    }
}

// MARK: - TimelineSegment

struct TimelineSegment: Identifiable {
    let id: String
    let start: Date
    let end: Date
    let appName: String
    let summary: String?
    let isIdle: Bool
    let color: Color
}

#Preview {
    TodayTimelineView(activities: [])
        .frame(width: 700, height: 120)
        .padding()
}
