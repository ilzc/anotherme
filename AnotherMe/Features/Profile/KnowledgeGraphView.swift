import SwiftUI

struct KnowledgeGraphView: View {
    @State private var graphNodes: [GraphNode] = []
    @State private var graphEdges: [GraphEdge] = []
    @State private var selectedNodeId: String?
    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    // MARK: - Graph Data Models

    struct GraphNode: Identifiable {
        let id: String
        let topic: String
        let category: String
        let totalTimeSpent: Int
        let visitCount: Int
        let depthScore: Double
        var position: CGPoint
        var velocity: CGPoint = .zero
    }

    struct GraphEdge: Identifiable {
        let id: String
        let sourceId: String
        let targetId: String
        let strength: Double
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            // Left: Graph Canvas
            graphCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))

            // Right: Detail panel
            if let nodeId = selectedNodeId,
               let node = graphNodes.first(where: { $0.id == nodeId }) {
                NodeDetailPanel(
                    node: node,
                    edges: graphEdges.filter { $0.sourceId == nodeId || $0.targetId == nodeId },
                    allNodes: graphNodes,
                    onDismiss: { selectedNodeId = nil }
                )
                .frame(width: 260)
            }
        }
        .task {
            loadGraphData()
            if !graphNodes.isEmpty {
                await runForceSimulation()
            }
        }
    }

    // MARK: - Graph Canvas

    @ViewBuilder
    private var graphCanvas: some View {
        if graphNodes.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "circle.grid.cross")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Insufficient knowledge graph data")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("At least 5 topic nodes required")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geometry in
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)

                    // Build O(1) lookup for node positions
                    var nodeIndexMap: [String: Int] = [:]
                    for (idx, node) in graphNodes.enumerated() {
                        nodeIndexMap[node.id] = idx
                    }

                    // Draw edges
                    for edge in graphEdges {
                        guard let si = nodeIndexMap[edge.sourceId],
                              let ti = nodeIndexMap[edge.targetId] else { continue }
                        let source = graphNodes[si]
                        let target = graphNodes[ti]
                        let from = transformPoint(source.position, center: center)
                        let to = transformPoint(target.position, center: center)
                        var path = Path()
                        path.move(to: from)
                        path.addLine(to: to)
                        let lineWidth = max(0.5, edge.strength * 3)
                        context.stroke(
                            path,
                            with: .color(.secondary.opacity(0.3 + edge.strength * 0.4)),
                            lineWidth: lineWidth
                        )
                    }

                    // Draw nodes
                    for node in graphNodes {
                        let pos = transformPoint(node.position, center: center)
                        let radius = nodeRadius(for: node)
                        let color = Self.categoryColor(node.category)
                        let isSelected = node.id == selectedNodeId

                        // Node circle
                        let rect = CGRect(
                            x: pos.x - radius,
                            y: pos.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(color.opacity(isSelected ? 1.0 : 0.7))
                        )
                        if isSelected {
                            context.stroke(
                                Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
                                with: .color(.accentColor),
                                lineWidth: 2
                            )
                        }

                        // Label
                        let text = Text(node.topic)
                            .font(.caption2)
                            .foregroundColor(.primary)
                        context.draw(
                            text,
                            at: CGPoint(x: pos.x, y: pos.y + radius + 10)
                        )
                    }
                }
                .gesture(magnificationGesture)
                .gesture(panGesture)
                .onTapGesture { location in
                    handleTap(at: location, in: geometry.size)
                }
            }
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(0.3, min(3.0, baseScale * value))
            }
            .onEnded { _ in
                baseScale = scale
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: dragStart.width + value.translation.width / scale,
                    height: dragStart.height + value.translation.height / scale
                )
            }
            .onEnded { _ in
                dragStart = offset
            }
    }

    // MARK: - Coordinate Transform

    private func transformPoint(_ point: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + (point.x + offset.width) * scale,
            y: center.y + (point.y + offset.height) * scale
        )
    }

    private func inverseTransformPoint(_ screenPoint: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(
            x: (screenPoint.x - center.x) / scale - offset.width,
            y: (screenPoint.y - center.y) / scale - offset.height
        )
    }

    // MARK: - Node Sizing

    private func nodeRadius(for node: GraphNode) -> CGFloat {
        let base: CGFloat = 8
        let factor = min(1.0, CGFloat(node.totalTimeSpent) / 36000.0) // cap at 10 hours
        return base + factor * 16
    }

    // MARK: - Category Colors

    static func categoryColor(_ category: String) -> Color {
        switch category {
        case "development": return .blue
        case "design": return .purple
        case "communication": return .green
        case "entertainment": return .orange
        case "research": return .cyan
        case "writing": return .pink
        default: return .gray
        }
    }

    // MARK: - Data Loading

    private func loadGraphData() {
        let dbm = DatabaseManager.shared
        guard let db = dbm.layer2DB else { return }
        let store = Layer2Store(db: db)

        do {
            let nodes = try store.fetchTopNodes(limit: 100)
            let edges = try store.fetchStrongestEdges(limit: 200)

            // Convert to graph nodes with random initial positions
            graphNodes = nodes.map { node in
                GraphNode(
                    id: node.id,
                    topic: node.topic,
                    category: node.category,
                    totalTimeSpent: node.totalTimeSpent,
                    visitCount: node.visitCount,
                    depthScore: node.depthScore,
                    position: CGPoint(
                        x: CGFloat.random(in: -200...200),
                        y: CGFloat.random(in: -200...200)
                    )
                )
            }

            // Only include edges where both endpoint nodes exist in the graph
            let nodeIds = Set(graphNodes.map(\.id))
            graphEdges = edges.compactMap { edge in
                guard nodeIds.contains(edge.sourceNodeId),
                      nodeIds.contains(edge.targetNodeId) else { return nil }
                return GraphEdge(
                    id: edge.id,
                    sourceId: edge.sourceNodeId,
                    targetId: edge.targetNodeId,
                    strength: edge.strength
                )
            }
        } catch {
            // Silently handle database errors; empty state UI will show
        }
    }

    // MARK: - Force-Directed Layout

    private func runForceSimulation() async {
        // Capture current state for off-main-thread computation
        var nodes = graphNodes
        let edges = graphEdges

        let finalNodes = await Task.detached(priority: .userInitiated) {
            Self.computeSimulation(nodes: &nodes, edges: edges, iterations: 120)
            return nodes
        }.value

        // Publish the final result back to @State in a single update
        graphNodes = finalNodes
    }

    /// Runs the full force-directed simulation off the main thread.
    nonisolated private static func computeSimulation(nodes: inout [GraphNode], edges: [GraphEdge], iterations: Int) {
        guard nodes.count > 1 else { return }

        // Build O(1) index lookup once
        var nodeIndexMap: [String: Int] = [:]
        nodeIndexMap.reserveCapacity(nodes.count)
        for (idx, node) in nodes.enumerated() {
            nodeIndexMap[node.id] = idx
        }

        let repulsion: CGFloat = 5000
        let attraction: CGFloat = 0.01
        let damping: CGFloat = 0.9
        let centerGravity: CGFloat = 0.01
        let maxVelocity: CGFloat = 10

        for _ in 0..<iterations {
            for i in 0..<nodes.count {
                var force = CGPoint.zero

                // Repulsion between all nodes
                for j in 0..<nodes.count where i != j {
                    let dx = nodes[i].position.x - nodes[j].position.x
                    let dy = nodes[i].position.y - nodes[j].position.y
                    let dist = max(1, sqrt(dx * dx + dy * dy))
                    let f = repulsion / (dist * dist)
                    force.x += (dx / dist) * f
                    force.y += (dy / dist) * f
                }

                // Attraction along edges (O(1) lookup)
                for edge in edges {
                    let otherIndex: Int?
                    if edge.sourceId == nodes[i].id {
                        otherIndex = nodeIndexMap[edge.targetId]
                    } else if edge.targetId == nodes[i].id {
                        otherIndex = nodeIndexMap[edge.sourceId]
                    } else {
                        otherIndex = nil
                    }
                    if let j = otherIndex {
                        let dx = nodes[j].position.x - nodes[i].position.x
                        let dy = nodes[j].position.y - nodes[i].position.y
                        force.x += dx * attraction * CGFloat(edge.strength)
                        force.y += dy * attraction * CGFloat(edge.strength)
                    }
                }

                // Pull towards center
                force.x -= nodes[i].position.x * centerGravity
                force.y -= nodes[i].position.y * centerGravity

                // Apply velocity with damping
                nodes[i].velocity.x = (nodes[i].velocity.x + force.x) * damping
                nodes[i].velocity.y = (nodes[i].velocity.y + force.y) * damping

                // Clamp velocity
                nodes[i].velocity.x = max(-maxVelocity, min(maxVelocity, nodes[i].velocity.x))
                nodes[i].velocity.y = max(-maxVelocity, min(maxVelocity, nodes[i].velocity.y))
            }

            // Update positions
            for i in 0..<nodes.count {
                nodes[i].position.x += nodes[i].velocity.x
                nodes[i].position.y += nodes[i].velocity.y
            }
        }
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let tapWorld = inverseTransformPoint(location, center: center)

        // Find nearest node within hit radius
        var bestId: String?
        var bestDist: CGFloat = .greatestFiniteMagnitude

        for node in graphNodes {
            let dx = node.position.x - tapWorld.x
            let dy = node.position.y - tapWorld.y
            let dist = sqrt(dx * dx + dy * dy)
            let hitRadius = (nodeRadius(for: node) / scale) + 4
            if dist < hitRadius && dist < bestDist {
                bestDist = dist
                bestId = node.id
            }
        }

        selectedNodeId = bestId
    }
}
