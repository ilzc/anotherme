import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(
                        message.role == "user"
                            ? Color.accentColor.opacity(0.15)
                            : Color(.controlBackgroundColor)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 4) {
                    if message.role == "agent", !message.referencedLayers.isEmpty {
                        ForEach(message.referencedLayers, id: \.self) { layer in
                            Text(layerLabel(layer))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if message.role == "agent" { Spacer(minLength: 60) }
        }
    }

    private func layerLabel(_ layer: Int) -> String {
        switch layer {
        case 1: return "Behavioral Rhythms"
        case 2: return "Knowledge Graph"
        case 3: return "Cognitive Style"
        case 4: return "Expression"
        case 5: return "Values"
        default: return "L\(layer)"
        }
    }
}
