import SwiftUI

struct NodeDetailPanel: View {
    let node: KnowledgeGraphView.GraphNode
    let edges: [KnowledgeGraphView.GraphEdge]
    let allNodes: [KnowledgeGraphView.GraphNode]
    var onDismiss: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.topic)
                            .font(.title2)
                            .bold()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(KnowledgeGraphView.categoryColor(node.category))
                                .frame(width: 8, height: 8)
                            Text(categoryLabel(node.category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let onDismiss {
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // Stats
                VStack(alignment: .leading, spacing: 10) {
                    statRow(label: "Total Time", value: formatDuration(node.totalTimeSpent))
                    statRow(label: "Visit Count", value: "\(node.visitCount) visits")
                    statRow(label: "Depth Score", value: String(format: "%.1f", node.depthScore))
                }

                Divider()

                // Connected nodes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Related Topics")
                        .font(.headline)

                    if connectedNodes.isEmpty {
                        Text("No related topics")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(connectedNodes, id: \.node.id) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(KnowledgeGraphView.categoryColor(item.node.category))
                                    .frame(width: 8, height: 8)
                                Text(item.node.topic)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%.0f%%", item.strength * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Connected Nodes

    private struct ConnectedItem {
        let node: KnowledgeGraphView.GraphNode
        let strength: Double
    }

    private var connectedNodes: [ConnectedItem] {
        edges.compactMap { edge in
            let otherId = edge.sourceId == node.id ? edge.targetId : edge.sourceId
            guard let other = allNodes.first(where: { $0.id == otherId }) else { return nil }
            return ConnectedItem(node: other, strength: edge.strength)
        }
        .sorted { $0.strength > $1.strength }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m"
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            if minutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(minutes)m"
        }
    }

    private func categoryLabel(_ category: String) -> String {
        switch category {
        case "development": return "Development"
        case "design": return "Design"
        case "communication": return "Communication"
        case "entertainment": return "Entertainment"
        case "research": return "Research"
        case "writing": return "Writing"
        default: return category
        }
    }
}
