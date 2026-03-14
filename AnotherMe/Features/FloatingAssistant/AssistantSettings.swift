import Foundation

/// Persists floating assistant preferences to UserDefaults.
struct AssistantSettings {
    private static let prefix = "floatingAssistant."

    private static let isVisibleKey = prefix + "isVisible"
    private static let positionXKey = prefix + "positionX"
    private static let positionYKey = prefix + "positionY"

    static var isVisible: Bool {
        get { UserDefaults.standard.bool(forKey: isVisibleKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: isVisibleKey) }
    }

    static var positionX: Double {
        get {
            UserDefaults.standard.object(forKey: positionXKey) != nil
                ? UserDefaults.standard.double(forKey: positionXKey)
                : -1
        }
        set { UserDefaults.standard.set(newValue, forKey: positionXKey) }
    }

    static var positionY: Double {
        get {
            UserDefaults.standard.object(forKey: positionYKey) != nil
                ? UserDefaults.standard.double(forKey: positionYKey)
                : -1
        }
        set { UserDefaults.standard.set(newValue, forKey: positionYKey) }
    }
}
