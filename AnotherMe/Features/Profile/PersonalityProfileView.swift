import SwiftUI

struct PersonalityProfileView: View {
    @State private var layer1Traits: [RhythmTrait] = []
    @State private var layer2Traits: [KnowledgeTrait] = []
    @State private var layer3Traits: [CognitiveTrait] = []
    @State private var layer4Traits: [ExpressionTrait] = []
    @State private var layer5Traits: [ValueTrait] = []
    @State private var latestSnapshot: PersonalitySnapshot?
    @State private var maturityData: MaturityData = MaturityData()

    private let analysisState = PersonalityAnalysisState.shared

    struct MaturityData {
        var totalRecords: Int = 0
        var topicRecords: Int = 0
        var textRecords: Int = 0
        var layer1Ready: Bool = false
        var layer2Ready: Bool = false
        var layer3Ready: Bool = false
        var layer4Ready: Bool = false
        var layer5Ready: Bool = false
    }

    private var allTraitsEmpty: Bool {
        layer1Traits.isEmpty && layer2Traits.isEmpty && layer3Traits.isEmpty
            && layer4Traits.isEmpty && layer5Traits.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Cold start maturity section
                ModelMaturityView(data: maturityData)

                // AI summary card
                if let snapshot = latestSnapshot,
                   let summary = snapshot.summaryText,
                   !summary.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(summary)
                                .font(.body)
                            Text(snapshot.snapshotDate, style: .date)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Label("AI Portrait Summary", systemImage: "sparkles")
                            .font(.headline)
                    }
                }

                // MBTI & Big Five Cards (always visible if any traits exist)
                if !allTraitsEmpty {
                    MBTICardView(
                        result: analysisState.mbtiResult,
                        isAnalyzing: analysisState.isMBTIAnalyzing,
                        onAnalyze: { analysisState.startMBTIAnalysis() },
                        analysisLog: analysisState.mbtiLog
                    )

                    BigFiveCardView(
                        result: analysisState.bigFiveResult,
                        isAnalyzing: analysisState.isBigFiveAnalyzing,
                        onAnalyze: { analysisState.startBigFiveAnalysis() },
                        analysisLog: analysisState.bigFiveLog
                    )
                }

                if allTraitsEmpty {
                    GroupBox {
                        VStack(spacing: 12) {
                            Image(systemName: "brain.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.quaternary)
                            Text("No personality data yet")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("The system is collecting your usage data. Analysis will begin automatically once enough records are accumulated.")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }

                // 5 layer trait cards (hidden when all empty — the consolidated empty state shows instead)
                if !allTraitsEmpty {
                TraitCardView(
                    title: "Behavioral Rhythms",
                    icon: "clock.fill",
                    color: .blue,
                    traits: layer1Traits.map {
                        .init(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
                    },
                    layer: 1
                )
                KnowledgeCardView(traits: layer2Traits)
                TraitCardView(
                    title: "Cognitive Style",
                    icon: "lightbulb.fill",
                    color: .orange,
                    traits: layer3Traits.map {
                        .init(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
                    },
                    layer: 3
                )
                TraitCardView(
                    title: "Expression",
                    icon: "text.bubble.fill",
                    color: .pink,
                    traits: layer4Traits.map {
                        .init(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
                    },
                    layer: 4
                )
                TraitCardView(
                    title: "Values",
                    icon: "heart.fill",
                    color: .purple,
                    traits: layer5Traits.map {
                        .init(dimension: $0.dimension, value: $0.value, confidence: $0.confidence)
                    },
                    layer: 5
                )
                } // end if !allTraitsEmpty
            }
            .padding()
        }
        .task { await loadData() }
    }

    // MARK: - Data Loading

    private func loadData() async {
        // Move all DB I/O off main thread
        let result: (
            l1: [RhythmTrait], l2: [KnowledgeTrait], l3: [CognitiveTrait],
            l4: [ExpressionTrait], l5: [ValueTrait],
            snapshot: PersonalitySnapshot?, maturity: MaturityData
        ) = await Task.detached {
            let dbm = DatabaseManager.shared
            var l1: [RhythmTrait] = []
            var l2: [KnowledgeTrait] = []
            var l3: [CognitiveTrait] = []
            var l4: [ExpressionTrait] = []
            var l5: [ValueTrait] = []
            var snapshot: PersonalitySnapshot? = nil
            var maturity = MaturityData()

            if let db = dbm.layer1DB { l1 = (try? Layer1Store(db: db).fetchTraits()) ?? [] }
            if let db = dbm.layer2DB { l2 = (try? Layer2Store(db: db).fetchTraits()) ?? [] }
            if let db = dbm.layer3DB { l3 = (try? Layer3Store(db: db).fetchTraits()) ?? [] }
            if let db = dbm.layer4DB { l4 = (try? Layer4Store(db: db).fetchTraits()) ?? [] }
            if let db = dbm.layer5DB { l5 = (try? Layer5Store(db: db).fetchTraits()) ?? [] }
            if let db = dbm.snapshotsDB {
                snapshot = try? SnapshotStore(db: db).fetchLatest()
            }

            if let db = dbm.activityDB {
                let total = (try? ActivityStore(db: db).totalCount()) ?? 0
                maturity.totalRecords = total
                maturity.layer1Ready = total >= 50
                maturity.layer2Ready = total >= 30
                maturity.layer3Ready = total >= 100
                maturity.layer4Ready = total >= 50
                maturity.layer5Ready = total >= 500
            }

            return (l1, l2, l3, l4, l5, snapshot, maturity)
        }.value

        // Single @State update on main thread
        layer1Traits = result.l1
        layer2Traits = result.l2
        layer3Traits = result.l3
        layer4Traits = result.l4
        layer5Traits = result.l5
        latestSnapshot = result.snapshot
        maturityData = result.maturity

        // Load MBTI/BigFive results into global state (only if not already loaded)
        analysisState.loadResults()
    }
}
