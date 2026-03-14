import SwiftUI

/// Displays Big Five (OCEAN) analysis result with 5-dimension visualization and evidence.
struct BigFiveCardView: View {
    let result: BigFiveResult?
    let isAnalyzing: Bool
    let onAnalyze: () -> Void
    var analysisLog: String = ""

    @State private var expandedDimension: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if isAnalyzing {
                    analyzingView
                } else if let result {
                    resultView(result)
                } else {
                    emptyView
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Label("Big Five Personality", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.teal)
                Spacer()
                if let result, !isAnalyzing {
                    Text("Confidence \(Int(result.overallConfidence * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 10) {
            Text("Big Five analysis not yet performed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Based on 5-layer personality data, AI will assess your scores across Openness, Conscientiousness, Extraversion, Agreeableness, and Neuroticism.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Start Analysis") { onAnalyze() }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Analyzing State

    private var analyzingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Analyzing Big Five...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !analysisLog.isEmpty {
                Text(analysisLog)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Result View

    private func resultView(_ r: BigFiveResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            dimensionRow(
                label: "O", name: "Openness", lowLabel: "Conservative", highLabel: "Innovative",
                score: r.opennessScore, confidence: r.opennessConfidence,
                strength: r.opennessStrength, evidence: r.opennessEvidence,
                color: .blue
            )
            dimensionRow(
                label: "C", name: "Conscientiousness", lowLabel: "Spontaneous", highLabel: "Disciplined",
                score: r.conscientiousnessScore, confidence: r.conscientiousnessConfidence,
                strength: r.conscientiousnessStrength, evidence: r.conscientiousnessEvidence,
                color: .green
            )
            dimensionRow(
                label: "E", name: "Extraversion", lowLabel: "Introverted", highLabel: "Sociable",
                score: r.extraversionScore, confidence: r.extraversionConfidence,
                strength: r.extraversionStrength, evidence: r.extraversionEvidence,
                color: .orange
            )
            dimensionRow(
                label: "A", name: "Agreeableness", lowLabel: "Competitive", highLabel: "Cooperative",
                score: r.agreeablenessScore, confidence: r.agreeablenessConfidence,
                strength: r.agreeablenessStrength, evidence: r.agreeablenessEvidence,
                color: .pink
            )
            dimensionRow(
                label: "N", name: "Neuroticism", lowLabel: "Calm", highLabel: "Anxious",
                score: r.neuroticismScore, confidence: r.neuroticismConfidence,
                strength: r.neuroticismStrength, evidence: r.neuroticismEvidence,
                color: .purple
            )

            Divider()

            // Summary
            Text(r.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(nil)

            // Re-analyze button
            HStack {
                Spacer()
                Text(r.analysisDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Button("Re-analyze") { onAnalyze() }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Dimension Row

    private func dimensionRow(
        label: String, name: String,
        lowLabel: String, highLabel: String,
        score: Double, confidence: Double,
        strength: String, evidence: String,
        color: Color
    ) -> some View {
        let isExpanded = expandedDimension == label
        let scorePercent = Int(score * 100)

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedDimension = isExpanded ? nil : label
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    // Title row
                    HStack {
                        Text(label)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(color)
                            .frame(width: 16)

                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .frame(width: 42, alignment: .leading)

                        Text(lowLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.1))

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color.opacity(0.6))
                                    .frame(width: geo.size.width * score)
                            }
                        }
                        .frame(height: 14)

                        Text(highLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .leading)

                        // Score
                        Text("\(scorePercent)%")
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(color)
                            .frame(width: 32, alignment: .trailing)

                        // Strength badge
                        Text(strength)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(strengthColor(strength).opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(strengthColor(strength))

                        // Confidence
                        Text("\(Int(confidence * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, alignment: .trailing)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Evidence (expanded)
            if isExpanded {
                let evidenceItems = parseEvidence(evidence)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(evidenceItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(item)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.leading, 60)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Helpers

    private func strengthColor(_ strength: String) -> Color {
        switch strength {
        case "强", "Strong": return .green
        case "中", "Medium": return .orange
        case "弱", "Weak": return .red
        default: return .gray
        }
    }

    private func parseEvidence(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return arr
    }
}
