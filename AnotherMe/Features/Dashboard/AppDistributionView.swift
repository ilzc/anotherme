import SwiftUI
import Charts

/// Donut chart showing app usage distribution by capture count.
struct AppDistributionView: View {
    let distribution: [(appName: String, count: Int)]

    var body: some View {
        GroupBox {
            if distribution.isEmpty {
                placeholder
            } else {
                chartContent
            }
        } label: {
            Label("App Distribution", systemImage: "chart.pie.fill")
                .font(.headline)
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartContent: some View {
        let items = buildChartItems()
        let total = items.reduce(0) { $0 + $1.count }

        HStack(alignment: .top, spacing: 24) {
            // Donut chart
            Chart(items) { item in
                SectorMark(
                    angle: .value("Count", item.count),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(item.color)
                .cornerRadius(3)
            }
            .frame(width: 180, height: 180)

            // Legend
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 10, height: 10)
                        Text(item.appName)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text(percentageText(count: item.count, total: total))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .frame(minWidth: 160)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Placeholder

    private var placeholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.pie")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No app distribution data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func buildChartItems() -> [AppChartItem] {
        // Show top 8 apps; merge the rest into "Other"
        let maxDisplay = 8
        var items: [AppChartItem] = []

        let sorted = distribution.sorted { $0.count > $1.count }
        let topApps = sorted.prefix(maxDisplay)
        let rest = sorted.dropFirst(maxDisplay)

        for (index, entry) in topApps.enumerated() {
            items.append(AppChartItem(
                appName: entry.appName,
                count: entry.count,
                color: Self.chartColor(at: index)
            ))
        }

        if !rest.isEmpty {
            let otherCount = rest.reduce(0) { $0 + $1.count }
            items.append(AppChartItem(
                appName: "Other",
                count: otherCount,
                color: .gray
            ))
        }

        return items
    }

    private func percentageText(count: Int, total: Int) -> String {
        guard total > 0 else { return "0%" }
        let pct = Double(count) / Double(total) * 100
        return String(format: "%.1f%%", pct)
    }

    static func chartColor(at index: Int) -> Color {
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .pink,
            .cyan, .indigo, .mint, .teal, .red,
            .yellow, .brown
        ]
        return palette[index % palette.count]
    }
}

// MARK: - AppChartItem

struct AppChartItem: Identifiable {
    let id = UUID()
    let appName: String
    let count: Int
    let color: Color
}

#Preview {
    AppDistributionView(distribution: [
        ("Xcode", 45),
        ("Safari", 30),
        ("Slack", 15),
        ("Terminal", 10)
    ])
    .frame(width: 500, height: 250)
    .padding()
}
