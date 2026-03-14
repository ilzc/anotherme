import AppKit

/// A non-activating panel that displays a brief scan-line animation
/// at the top of the screen each time a screenshot is taken.
final class CaptureAnimationWindow: NSPanel {
    private let animationLayer = CAGradientLayer()
    private let barHeight: CGFloat = 3

    init() {
        guard let screen = NSScreen.main else {
            super.init(
                contentRect: .zero,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: true
            )
            return
        }

        let frame = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.maxY - screen.frame.origin.y - barHeight,
            width: screen.frame.width,
            height: barHeight
        )

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.hasShadow = false

        setupAnimationLayer()
    }

    private func setupAnimationLayer() {
        guard let contentView else { return }
        contentView.wantsLayer = true

        animationLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor,
            NSColor.controlAccentColor.cgColor,
            NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor,
            NSColor.clear.cgColor
        ]
        animationLayer.locations = [0.0, 0.3, 0.5, 0.7, 1.0]
        animationLayer.startPoint = CGPoint(x: 0, y: 0.5)
        animationLayer.endPoint = CGPoint(x: 1, y: 0.5)
        animationLayer.frame = CGRect(x: -contentView.bounds.width, y: 0,
                                       width: contentView.bounds.width, height: barHeight)
        animationLayer.opacity = 0

        contentView.layer?.addSublayer(animationLayer)
    }

    func playAnimation() {
        guard let screen = NSScreen.main, let contentView else { return }

        // Reposition in case screen changed
        let frame = NSRect(
            x: screen.frame.origin.x,
            y: screen.visibleFrame.maxY - barHeight,
            width: screen.frame.width,
            height: barHeight
        )
        setFrame(frame, display: false)

        // Show
        orderFrontRegardless()
        animationLayer.opacity = 1
        animationLayer.frame = CGRect(
            x: -contentView.bounds.width, y: 0,
            width: contentView.bounds.width, height: barHeight
        )

        // Animate: sweep from left to right
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        CATransaction.setCompletionBlock { [weak self] in
            self?.animationLayer.opacity = 0
            self?.orderOut(nil)
        }

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -contentView.bounds.width / 2
        animation.toValue = contentView.bounds.width + contentView.bounds.width / 2
        animation.duration = 0.5
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animationLayer.add(animation, forKey: "sweep")
        animationLayer.position.x = contentView.bounds.width + contentView.bounds.width / 2

        CATransaction.commit()
    }
}
