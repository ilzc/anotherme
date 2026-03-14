import Foundation
import AppKit
import ApplicationServices

/// Observes the focused window's title changes via Accessibility API.
/// Triggers a callback when the title changes (e.g., browser tab switch).
final class WindowObserver {
    private var observer: AXObserver?
    private var currentApp: NSRunningApplication?
    private var currentElement: AXUIElement?
    private var appObserver: NSObjectProtocol?

    var onWindowTitleChanged: (() -> Void)?

    // MARK: - Start / Stop

    func start() {
        // Watch for active app changes to re-attach observer
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.attachToApp(app)
        }

        // Attach to current frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            attachToApp(frontApp)
        }
    }

    func stop() {
        if let appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
        }
        appObserver = nil
        detachFromCurrentApp()
    }

    deinit {
        stop()
    }

    // MARK: - Private

    private func attachToApp(_ app: NSRunningApplication) {
        // Skip if already observing this app
        if currentApp?.processIdentifier == app.processIdentifier { return }

        detachFromCurrentApp()
        currentApp = app

        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        currentElement = element

        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let observer = Unmanaged<WindowObserver>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                observer.onWindowTitleChanged?()
            }
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverCreate(pid, callback, &obs)

        guard result == .success, let obs else { return }
        observer = obs

        // Observe title changes on the focused window
        AXObserverAddNotification(obs, element, kAXFocusedWindowChangedNotification as CFString, selfPtr)
        AXObserverAddNotification(obs, element, kAXTitleChangedNotification as CFString, selfPtr)

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .commonModes
        )
    }

    private func detachFromCurrentApp() {
        if let obs = observer {
            if let element = currentElement {
                AXObserverRemoveNotification(obs, element, kAXFocusedWindowChangedNotification as CFString)
                AXObserverRemoveNotification(obs, element, kAXTitleChangedNotification as CFString)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(obs),
                .commonModes
            )
        }
        observer = nil
        currentElement = nil
        currentApp = nil
    }

    /// Get the current focused window title (useful for logging)
    func currentWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard result == .success else { return nil }

        guard let focusedWindow else { return nil }
        // CFTypeRef from AXUIElementCopyAttributeValue is guaranteed to be AXUIElement for focused window
        let windowElement = focusedWindow as! AXUIElement

        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title)
        guard titleResult == .success else { return nil }

        return title as? String
    }
}
