import AppKit

enum PositionStore {
    private static let xKey = "cloudTopX"
    private static let yKey = "cloudTopY"

    static func save(frame: NSRect) {
        UserDefaults.standard.set(Double(frame.origin.x), forKey: xKey)
        UserDefaults.standard.set(Double(frame.origin.y + frame.height), forKey: yKey)
    }

    static func savedTopLeft() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: xKey) != nil else { return nil }
        return NSPoint(x: defaults.double(forKey: xKey), y: defaults.double(forKey: yKey))
    }
}

final class CloudPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Chrome.collapsed),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            makeKey()
        }
        super.sendEvent(event)
    }
}
