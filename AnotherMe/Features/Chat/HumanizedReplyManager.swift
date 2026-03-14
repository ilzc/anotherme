import Foundation

/// Splits a full LLM reply into segments and delivers them with human-like timing.
/// Timing is driven by Layer4 expression personality traits.
@MainActor
final class HumanizedReplyManager {

    enum ResponseSpeed: String {
        case fast    // verbose
        case medium
        case slow    // concise
    }

    /// Split full reply into segments and deliver them with delays.
    /// Calls `onSegment` for each segment. Completes when all segments are delivered.
    func deliver(
        fullReply: String,
        responseSpeed: ResponseSpeed = .medium,
        onSegment: @escaping (String) -> Void
    ) async {
        let segments = splitIntoSegments(fullReply)

        for (index, segment) in segments.enumerated() {
            if index > 0 {
                let delay = calculateDelay(baseDelay: responseSpeed)
                try? await Task.sleep(for: .seconds(delay))
            }
            onSegment(segment)
        }
    }

    /// Split text into natural segments (by double newline / paragraphs).
    /// Short adjacent paragraphs may be merged to avoid single-word messages.
    func splitIntoSegments(_ text: String) -> [String] {
        let rawSegments = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // If only one segment or none, return as-is
        guard rawSegments.count > 1 else { return rawSegments.isEmpty ? [text] : rawSegments }

        // Merge very short segments (< 20 chars) with the next one
        var merged: [String] = []
        var buffer = ""
        for segment in rawSegments {
            if buffer.isEmpty {
                buffer = segment
            } else if buffer.count < 20 {
                buffer += "\n\n" + segment
            } else {
                merged.append(buffer)
                buffer = segment
            }
        }
        if !buffer.isEmpty {
            merged.append(buffer)
        }

        return merged
    }

    func calculateDelay(baseDelay: ResponseSpeed) -> TimeInterval {
        let base: TimeInterval
        switch baseDelay {
        case .fast:   base = 1.0
        case .medium: base = 2.5
        case .slow:   base = 4.0
        }
        // Randomize +/-30%
        let jitter = base * Double.random(in: -0.3...0.3)
        return max(0.5, base + jitter)
    }
}
