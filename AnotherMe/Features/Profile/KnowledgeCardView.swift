import SwiftUI

/// Rich visualization card for Layer 2 (Interest & Knowledge) data.
/// Directly reads KnowledgeNode data for charts instead of showing raw text.
struct KnowledgeCardView: View {
    let traits: [KnowledgeTrait]

    @State private var nodes: [KnowledgeNode] = []
    @State private var isLoaded = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                if !isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if nodes.isEmpty && traits.isEmpty {
                    emptyState
                } else {
                    if !nodes.isEmpty {
                        overviewMetrics
                        Divider()
                        domainDistributionChart
                        Divider()
                        depthDistributionBar
                        Divider()
                        topTopicsTags
                    }
                    if !traits.isEmpty {
                        if !nodes.isEmpty { Divider() }
                        aiInsightsSection
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Label("Knowledge & Interests", systemImage: "brain.head.profile")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                if !nodes.isEmpty {
                    Text("\(nodes.count) topics")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { loadNodes() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack {
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
            Text("Collecting data...")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Overview Metrics

    private var overviewMetrics: some View {
        let categories = Set(nodes.map(\.category))
        let diversityIndex = min(1.0, Double(categories.count) / 8.0)
        let recentNodes = nodes.filter { $0.lastSeen > Date().addingTimeInterval(-7 * 86400) }
        let totalHours = nodes.reduce(0) { $0 + $1.totalTimeSpent } / 3600

        return HStack(spacing: 0) {
            metricCell(value: "\(nodes.count)", label: "Total Topics", icon: "number")
            Divider().frame(height: 36)
            metricCell(value: "\(Int(diversityIndex * 100))%", label: "Diversity", icon: "chart.pie")
            Divider().frame(height: 36)
            metricCell(value: "\(recentNodes.count)", label: "Active (7d)", icon: "flame")
            Divider().frame(height: 36)
            metricCell(value: "\(totalHours)h", label: "Total Time", icon: "clock")
        }
    }

    private func metricCell(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.monospacedDigit().bold())
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Domain Distribution (Horizontal Bar Chart)

    private var domainDistributionChart: some View {
        let distribution = Dictionary(grouping: nodes, by: \.category)
            .map { DomainEntry(category: Self.categoryDisplayName($0.key), count: $0.value.count, color: Self.categoryColor($0.key)) }
            .sorted { $0.count > $1.count }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Domain Distribution")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if distribution.count <= 8 {
                // Horizontal bars for manageable count
                ForEach(distribution, id: \.category) { entry in
                    domainBar(entry: entry, maxCount: distribution.first?.count ?? 1)
                }
            } else {
                // Show top 8 + "Other"
                let top8 = Array(distribution.prefix(8))
                let otherCount = distribution.dropFirst(8).reduce(0) { $0 + $1.count }
                ForEach(top8, id: \.category) { entry in
                    domainBar(entry: entry, maxCount: distribution.first?.count ?? 1)
                }
                if otherCount > 0 {
                    domainBar(
                        entry: DomainEntry(category: "Other", count: otherCount, color: .gray),
                        maxCount: distribution.first?.count ?? 1
                    )
                }
            }
        }
    }

    private func domainBar(entry: DomainEntry, maxCount: Int) -> some View {
        HStack(spacing: 8) {
            Text(entry.category)
                .font(.caption)
                .frame(width: 56, alignment: .trailing)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let ratio = maxCount > 0 ? CGFloat(entry.count) / CGFloat(maxCount) : 0
                RoundedRectangle(cornerRadius: 3)
                    .fill(entry.color.opacity(0.7))
                    .frame(width: max(2, geo.size.width * ratio))
            }
            .frame(height: 14)

            Text("\(entry.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .leading)
        }
        .frame(height: 18)
    }

    // MARK: - Depth Distribution (Segmented Bar)

    private var depthDistributionBar: some View {
        let shallow = nodes.filter { $0.depthScore < 0.2 }.count
        let moderate = nodes.filter { $0.depthScore >= 0.2 && $0.depthScore < 0.5 }.count
        let deep = nodes.filter { $0.depthScore >= 0.5 && $0.depthScore < 0.8 }.count
        let expert = nodes.filter { $0.depthScore >= 0.8 }.count
        let total = max(1, nodes.count)

        let segments: [(String, Int, Color)] = [
            ("Shallow", shallow, .gray),
            ("Moderate", moderate, .blue),
            ("Deep", deep, .orange),
            ("Expert", expert, .red),
        ]

        return VStack(alignment: .leading, spacing: 6) {
            Text("Knowledge Depth Distribution")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            // Segmented bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segments, id: \.0) { label, count, color in
                        if count > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.opacity(0.7))
                                .frame(width: max(2, geo.size.width * CGFloat(count) / CGFloat(total)))
                        }
                    }
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // Legend
            HStack(spacing: 12) {
                ForEach(segments, id: \.0) { label, count, color in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(color.opacity(0.7))
                            .frame(width: 7, height: 7)
                        Text("\(label) \(count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Top Topics Tags

    private var topTopicsTags: some View {
        let topNodes = Array(nodes.sorted { $0.totalTimeSpent > $1.totalTimeSpent }.prefix(20))

        return VStack(alignment: .leading, spacing: 6) {
            Text("Top Topics")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(topNodes) { node in
                    topicTag(node)
                }
            }
        }
    }

    private func topicTag(_ node: KnowledgeNode) -> some View {
        let hours = Double(node.totalTimeSpent) / 3600.0
        let depthColor = depthColor(for: node.depthScore)

        return HStack(spacing: 3) {
            Circle()
                .fill(depthColor)
                .frame(width: 6, height: 6)
            Text(node.topic)
                .font(.caption)
            if hours >= 1.0 {
                Text(String(format: "%.0fh", hours))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(depthColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private func depthColor(for score: Double) -> Color {
        switch score {
        case 0.8...: return .red
        case 0.5..<0.8: return .orange
        case 0.2..<0.5: return .blue
        default: return .gray
        }
    }

    // MARK: - AI Insights (Collapsible)

    @State private var showAIInsights = false

    private var aiInsightsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation { showAIInsights.toggle() }
            } label: {
                HStack {
                    Label("AI Insights", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showAIInsights ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if showAIInsights {
                ForEach(traits, id: \.id) { trait in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(Self.dimensionDisplayName(trait.dimension))
                                .font(.caption.bold())
                            Text("(Confidence: \(Int(trait.confidence * 100))%)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(trait.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadNodes() {
        guard let db = DatabaseManager.shared.layer2DB else {
            isLoaded = true
            return
        }
        let store = Layer2Store(db: db)
        do {
            nodes = try store.fetchAllNodes()
        } catch {
            nodes = []
        }
        isLoaded = true
    }

    // MARK: - Helpers

    private struct DomainEntry {
        let category: String
        let count: Int
        let color: Color
    }

    static func categoryDisplayName(_ category: String) -> String {
        let map: [String: String] = [
            "work": "Work",
            "social": "Social",
            "learning": "Learning",
            "entertainment": "Entertainment",
            "finance": "Finance",
            "development": "Development",
            "design": "Design",
            "communication": "Communication",
            "research": "Research",
            "writing": "Writing",
            "other": "Other",
        ]
        return map[category] ?? category
    }

    static func categoryColor(_ category: String) -> Color {
        switch category {
        case "work": return .blue
        case "social": return .green
        case "learning": return .cyan
        case "entertainment": return .orange
        case "finance": return .yellow
        case "development": return .indigo
        case "design": return .purple
        case "communication": return .mint
        case "research": return .teal
        case "writing": return .pink
        default: return .gray
        }
    }

    static func dimensionDisplayName(_ dim: String) -> String {
        let map: [String: String] = [
            "knowledge_breadth": "Knowledge Breadth",
            "knowledge_depth": "Knowledge Depth",
            "learning_style": "Learning Style",
            "interest_evolution": "Interest Evolution",
        ]
        return map[dim] ?? dim
    }
}

// MARK: - Flow Layout (Tag Cloud)

/// Simple flow layout that wraps children to next line when horizontal space runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x)
            totalHeight = max(totalHeight, y + rowHeight)
        }

        return ArrangeResult(
            size: CGSize(width: totalWidth, height: totalHeight),
            positions: positions
        )
    }
}
