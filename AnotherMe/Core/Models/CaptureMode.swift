import Foundation

enum CaptureMode: String, Codable, CaseIterable {
    case interval   // Fixed interval
    case event      // Event-driven
    case smart      // Smart sampling
}
