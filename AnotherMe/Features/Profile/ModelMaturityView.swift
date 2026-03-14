import SwiftUI

struct ModelMaturityView: View {
    let data: PersonalityProfileView.MaturityData

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                maturityRow("Behavioral Rhythm", current: data.totalRecords, target: 50, ready: data.layer1Ready, color: .blue)
                maturityRow("Knowledge Graph", current: data.totalRecords, target: 30, ready: data.layer2Ready, color: .green)
                maturityRow("Cognitive Style", current: data.totalRecords, target: 100, ready: data.layer3Ready, color: .orange)
                maturityRow("Expressive Persona", current: data.totalRecords, target: 50, ready: data.layer4Ready, color: .pink)
                maturityRow("Values", current: data.totalRecords, target: 500, ready: data.layer5Ready, color: .purple)
            }
            .padding(.vertical, 4)
        } label: {
            Label("Model Maturity", systemImage: "chart.bar.fill")
                .font(.headline)
        }
    }

    @ViewBuilder
    private func maturityRow(_ title: String, current: Int, target: Int, ready: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                if ready {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("\(Int(min(1.0, Double(current) / Double(target)) * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ready ? Color.green : color)
                        .frame(width: geo.size.width * min(1.0, CGFloat(current) / CGFloat(target)))
                }
            }
            .frame(height: 6)

            Text("\(current)/\(target) records")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
