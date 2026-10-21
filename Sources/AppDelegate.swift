import AppKit
import Combine

extension Notification.Name {
    static let cloudetShowCloud = Notification.Name("app.cloudet.mac.show")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = BufferModel(store: .live())
    private var panel: CloudPanel?
    private var statusItem: NSStatusItem?
    private var layoutCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showFromAnotherLaunch),
            name: .cloudetShowCloud,
            object: nil
        )
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = CloudIcon.menuImage()
            button.image = image
            button.toolTip = "Cloudet"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: L10n.tr("Show Cloud"), action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: L10n.tr("Open Copies in Finder"), action: #selector(openBufferFolder), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("Clear Cloud"), action: #selector(clearBuffer), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("Quit Cloudet"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items {
            item.target = self
        }
        item.menu = menu
        statusItem = item
    }

    private func setupPanel() {
        let root = RootDropView(model: model)
        let panel = CloudPanel(contentView: root)
        self.panel = panel
        layoutCancellable = Publishers.CombineLatest3(model.$expanded, model.$files, model.$lastError)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.layoutPanel(animated: true)
            }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.model.expanded == true, NSApp.modalWindow == nil else { return event }
            self?.model.expanded = false
            return nil
        }
        layoutPanel(animated: false)
        panel.orderFrontRegardless()
    }

    private func layoutPanel(animated: Bool) {
        guard let panel else { return }
        let size = model.preferredSize
        let topLeft = currentTopLeft(for: panel, size: size)
        var frame = NSRect(
            x: topLeft.x,
            y: topLeft.y - size.height,
            width: size.width,
            height: size.height
        )
        frame = clamped(frame)
        panel.setFrame(frame, display: true, animate: animated && panel.isVisible)
    }

    private func currentTopLeft(for panel: CloudPanel, size: NSSize) -> NSPoint {
        if panel.isVisible, panel.frame.width > 1 {
            return NSPoint(x: panel.frame.origin.x, y: panel.frame.origin.y + panel.frame.height)
        }
        if let saved = PositionStore.savedTopLeft() {
            return saved
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NSPoint(x: screen.maxX - size.width - 36, y: screen.midY + size.height / 2)
    }

    private func clamped(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        let anchor = NSPoint(x: frame.midX, y: frame.midY)
        let screen = screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let screen else { return frame }
        let vis = screen.visibleFrame
        var result = frame
        result.origin.x = min(max(result.origin.x, vis.minX + 8), vis.maxX - result.width - 8)
        result.origin.y = min(max(result.origin.y, vis.minY + 8), vis.maxY - result.height - 8)
        return result
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(togglePanel) }?.title =
            (panel?.isVisible == true) ? L10n.tr("Hide Cloud") : L10n.tr("Show Cloud")
        menu.items.first { $0.action == #selector(clearBuffer) }?.isEnabled = !model.files.isEmpty
    }

    @objc private func showFromAnotherLaunch() {
        if Thread.isMainThread {
            revealCloud()
        } else {
            perform(#selector(revealCloud), on: Thread.main, with: nil, waitUntilDone: false)
        }
    }

    @objc private func revealCloud() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderFrontRegardless()
        } else {
            togglePanel()
        }
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            PositionStore.save(frame: panel.frame)
            panel.orderOut(nil)
        } else {
            layoutPanel(animated: false)
            panel.orderFrontRegardless()
        }
    }

    @objc private func openBufferFolder() {
        try? model.store.prepare()
        NSWorkspace.shared.open(model.store.filesRoot)
    }

    @objc private func clearBuffer() {
        guard !model.files.isEmpty else { return }
        model.clear()
    }

    @objc private func quit() {
        if let panel {
            PositionStore.save(frame: panel.frame)
        }
        NSApp.terminate(nil)
    }
}
