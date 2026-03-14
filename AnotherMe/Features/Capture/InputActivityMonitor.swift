import Foundation
import CoreGraphics

/// Monitors global mouse/keyboard events via CGEvent tap to detect user activity.
/// Requires Accessibility permission.
final class InputActivityMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var stopped = false
    private(set) var lastInputTime: Date = .now

    /// Current idle duration in seconds
    var idleDuration: TimeInterval {
        Date.now.timeIntervalSince(lastInputTime)
    }

    enum ActivityLevel {
        case active          // < 2 min since last input
        case idle            // 2-10 min since last input
        case deepIdle        // > 10 min since last input

        init(idleSeconds: TimeInterval) {
            switch idleSeconds {
            case ..<120:    self = .active
            case ..<600:    self = .idle
            default:        self = .deepIdle
            }
        }
    }

    var activityLevel: ActivityLevel {
        ActivityLevel(idleSeconds: idleDuration)
    }

    // MARK: - Start / Stop

    func start() -> Bool {
        let eventMask: CGEventMask = (
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        )

        stopped = false

        // The callback must be a C function pointer, so we use a static context.
        // We check the `stopped` flag to avoid accessing a potentially deallocated object.
        let callback: CGEventTapCallBack = { _, _, _, refcon in
            guard let refcon else { return nil }
            let monitor = Unmanaged<InputActivityMonitor>.fromOpaque(refcon).takeUnretainedValue()
            guard !monitor.stopped else { return nil }
            monitor.lastInputTime = .now
            return nil // Pass event through, don't consume it
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,       // Passive listener, doesn't modify events
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            return false // Accessibility permission not granted
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    func stop() {
        // Set stopped flag first to prevent the callback from accessing self
        stopped = true

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    deinit {
        stop()
    }
}
