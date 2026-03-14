import SwiftUI

/// Displays MBTI analysis result with 4-dimension visualization and evidence.
struct MBTICardView: View {
    let result: MBTIResult?
    let isAnalyzing: Bool
    let onAnalyze: () -> Void
    var analysisLog: String = ""

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
                Label("MBTI Personality Type", systemImage: "person.crop.rectangle.stack")
                    .font(.headline)
                    .foregroundStyle(.indigo)
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
            Text("MBTI analysis not yet performed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Based on 5-layer personality data, AI will infer your MBTI type")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Start Analysis") { onAnalyze() }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Analyzing State

    private var analyzingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Analyzing MBTI...")
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

    private func resultView(_ r: MBTIResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Big MBTI type display
            mbtiTypeHeader(r)

            Divider()

            // 4 dimension bars
            dimensionRow(label: "E / I", leftLetter: "E", rightLetter: "I",
                         leftName: "Extraversion", rightName: "Introversion",
                         result: r.eiResult, confidence: r.eiConfidence,
                         strength: r.eiStrength, evidence: r.eiEvidence)

            dimensionRow(label: "S / N", leftLetter: "S", rightLetter: "N",
                         leftName: "Sensing", rightName: "Intuition",
                         result: r.snResult, confidence: r.snConfidence,
                         strength: r.snStrength, evidence: r.snEvidence)

            dimensionRow(label: "T / F", leftLetter: "T", rightLetter: "F",
                         leftName: "Thinking", rightName: "Feeling",
                         result: r.tfResult, confidence: r.tfConfidence,
                         strength: r.tfStrength, evidence: r.tfEvidence)

            dimensionRow(label: "J / P", leftLetter: "J", rightLetter: "P",
                         leftName: "Judging", rightName: "Perceiving",
                         result: r.jpResult, confidence: r.jpConfidence,
                         strength: r.jpStrength, evidence: r.jpEvidence)

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

    // MARK: - MBTI Type Header

    private func mbtiTypeHeader(_ r: MBTIResult) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(r.mbtiType.enumerated()), id: \.offset) { _, char in
                Text(String(char))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.indigo)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(mbtiTypeName(r.mbtiType))
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text("Overall Confidence \(Int(r.overallConfidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Dimension Row

    @State private var expandedDimension: String?

    private func dimensionRow(
        label: String, leftLetter: String, rightLetter: String,
        leftName: String, rightName: String,
        result: String, confidence: Double,
        strength: String, evidence: String
    ) -> some View {
        let isLeft = result == leftLetter
        let barRatio = confidence  // confidence as visual indicator
        let isExpanded = expandedDimension == label

        return VStack(alignment: .leading, spacing: 4) {
            // Tap to expand evidence
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedDimension = isExpanded ? nil : label
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // Left label
                        Text("\(leftLetter) \(leftName)")
                            .font(.caption)
                            .fontWeight(isLeft ? .bold : .regular)
                            .foregroundStyle(isLeft ? .indigo : .secondary)
                            .frame(width: 50, alignment: .trailing)

                        // Bar
                        GeometryReader { geo in
                            ZStack {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.1))

                                HStack(spacing: 0) {
                                    if isLeft {
                                        // Bar grows from center toward left
                                        Spacer()
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.indigo.opacity(0.6))
                                            .frame(width: geo.size.width * 0.5 * barRatio)
                                        Spacer()
                                            .frame(width: geo.size.width * 0.5)
                                    } else {
                                        // Bar grows from center toward right
                                        Spacer()
                                            .frame(width: geo.size.width * 0.5)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.indigo.opacity(0.6))
                                            .frame(width: geo.size.width * 0.5 * barRatio)
                                        Spacer()
                                    }
                                }

                                // Center line
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: 1)
                            }
                        }
                        .frame(height: 16)

                        // Right label
                        Text("\(rightLetter) \(rightName)")
                            .font(.caption)
                            .fontWeight(!isLeft ? .bold : .regular)
                            .foregroundStyle(!isLeft ? .indigo : .secondary)
                            .frame(width: 50, alignment: .leading)

                        // Strength + confidence
                        Text("\(strength)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(strengthColor(strength).opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(strengthColor(strength))

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
                .padding(.leading, 54)
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

    private func mbtiTypeName(_ type: String) -> String {
        let names: [String: String] = [
            "INTJ": "Architect", "INTP": "Logician", "ENTJ": "Commander", "ENTP": "Debater",
            "INFJ": "Advocate", "INFP": "Mediator", "ENFJ": "Protagonist", "ENFP": "Campaigner",
            "ISTJ": "Logistician", "ISFJ": "Defender", "ESTJ": "Executive", "ESFJ": "Consul",
            "ISTP": "Virtuoso", "ISFP": "Adventurer", "ESTP": "Entrepreneur", "ESFP": "Entertainer",
        ]
        return names[type] ?? type
    }
}
