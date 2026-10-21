import AppKit
import Combine
import SwiftUI

final class RootDropView: NSView {
    let model: BufferModel
    private let container: NSView
    private let column: NSView
    private let cloudGlass: NSView
    private let cloudRim: CloudRimView
    private let captionHost: NSHostingView<CloudLabel>
    private let shelfGlass: NSView
    private let spinner: NSProgressIndicator
    private let cloudDrag: WindowDragNSView
    private var changeObserver: AnyCancellable?

    init(model: BufferModel) {
        self.model = model
        container = LiquidGlass.container(spacing: 0)
        column = NSView(frame: .zero)
        cloudGlass = LiquidGlass.effect(radius: 0, interactive: true)
        cloudRim = CloudRimView()
        captionHost = NSHostingView(rootView: CloudLabel(model: model))
        shelfGlass = LiquidGlass.effect(radius: Chrome.shelfRadius, interactive: false)
        spinner = NSProgressIndicator()
        cloudDrag = WindowDragNSView()
        super.init(frame: NSRect(origin: .zero, size: Chrome.collapsed))

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        column.wantsLayer = true
        column.layer?.backgroundColor = NSColor.clear.cgColor

        let shelfHost = NSHostingView(rootView: Shelf(model: model))
        prepare(shelfHost)
        prepare(captionHost)
        LiquidGlass.embed(shelfHost, in: shelfGlass)
        LiquidGlass.embed(captionHost, in: cloudGlass)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true

        column.addSubview(shelfGlass)
        column.addSubview(cloudGlass)
        column.addSubview(cloudRim)
        column.addSubview(spinner)
        LiquidGlass.place(column, in: container)
        addSubview(container)
        addSubview(cloudDrag)

        cloudDrag.onClick = { [weak model] in model?.expanded.toggle() }
        registerForDraggedTypes(ImageDrop.pasteboardTypes)
        changeObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsLayout = true }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func prepare<V: View>(_ host: NSHostingView<V>) {
        host.wantsLayer = true
        host.layer?.isOpaque = false
        host.layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 13.0, *) {
            host.sizingOptions = []
        }
        if #available(macOS 14.0, *) {
            host.safeAreaRegions = []
        }
    }

    override func layout() {
        super.layout()
        container.frame = bounds
        column.frame = bounds

        let size = Chrome.cloud
        let cloud = NSRect(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - size.height - Chrome.topInset,
            width: size.width,
            height: size.height
        )
        cloudGlass.frame = cloud
        cloudRim.frame = cloud.insetBy(dx: -4, dy: -4)
        let local = CGRect(origin: .zero, size: cloud.size)
        LiquidGlass.setPath(CloudShape.cgPath(in: local), on: cloudGlass)
        if let content = LiquidGlass.contentView(of: cloudGlass) {
            content.frame = cloudGlass.bounds
        }
        let outline = CloudShape.bezier(in: local)
        cloudRim.update(
            CloudShape.bezier(in: CGRect(x: 4, y: 4, width: cloud.width, height: cloud.height)),
            highlighted: model.isDragTarget
        )
        cloudDrag.frame = cloud
        cloudDrag.shape = outline
        let spinnerSide: CGFloat = 16
        spinner.frame = NSRect(
            x: cloud.midX - spinnerSide / 2,
            y: cloud.maxY - 40,
            width: spinnerSide,
            height: spinnerSide
        )
        if model.isCopying {
            if spinner.isHidden {
                spinner.isHidden = false
                spinner.startAnimation(nil)
            }
        } else if !spinner.isHidden {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        }

        let showShelf = model.expanded
        shelfGlass.isHidden = !showShelf
        guard showShelf else { return }
        let shelfY = Chrome.bottomInset
        let shelfHeight = max(40, cloud.minY - Chrome.gap - shelfY)
        shelfGlass.frame = NSRect(
            x: Chrome.sideInset,
            y: shelfY,
            width: bounds.width - Chrome.sideInset * 2,
            height: shelfHeight
        )
        if let content = LiquidGlass.contentView(of: shelfGlass) {
            content.frame = shelfGlass.bounds
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    private func wantsDrop(_ pasteboard: NSPasteboard) -> Bool {
        let urls = fileURLs(from: pasteboard)
        if !urls.isEmpty {
            return !urls.allSatisfy { model.store.contains($0) }
        }
        return ImageDrop.canAccept(pasteboard)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard wantsDrop(sender.draggingPasteboard) else {
            model.isDragTarget = false
            return []
        }
        model.isDragTarget = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        model.isDragTarget ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.isDragTarget = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model.isDragTarget = false
        let pasteboard = sender.draggingPasteboard
        let urls = fileURLs(from: pasteboard).filter { !model.store.contains($0) }
        if !urls.isEmpty {
            model.accept(urls: urls)
            return true
        }
        return model.acceptPasteboard(pasteboard)
    }
}

final class CloudRimView: NSView {
    private let stroke = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        stroke.fillColor = nil
        stroke.lineJoin = .round
        stroke.lineCap = .round
        stroke.lineWidth = 3.5
        layer?.addSublayer(stroke)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ path: NSBezierPath, highlighted: Bool) {
        stroke.frame = bounds
        stroke.path = path.cgPath
        stroke.lineWidth = highlighted ? 5 : 3.5
        stroke.contentsScale = window?.backingScaleFactor ?? 2
        applyColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    private func applyColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            stroke.strokeColor = NSColor.labelColor.cgColor
        }
    }
}

final class WindowDragNSView: NSView {
    var onClick: () -> Void = {}
    var shape = NSBezierPath(rect: .zero)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard shape.bounds.isEmpty || shape.contains(local) else { return nil }
        return self
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let start = NSEvent.mouseLocation
        let origin = window?.frame.origin ?? .zero
        var dragged = false

        while true {
            guard let next = NSApp.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { return }

            if next.type == .leftMouseUp {
                if dragged, let frame = window?.frame {
                    PositionStore.save(frame: frame)
                } else if !dragged {
                    onClick()
                }
                return
            }

            let now = NSEvent.mouseLocation
            let dx = now.x - start.x
            let dy = now.y - start.y
            if hypot(dx, dy) > 3 {
                dragged = true
                window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            }
        }
    }
}

struct FileDragPad: NSViewRepresentable {
    var url: URL
    var onHover: (Bool) -> Void
    var onRemove: () -> Void

    func makeNSView(context: Context) -> FileDragNSView {
        let view = FileDragNSView()
        view.url = url
        view.onHover = onHover
        view.onRemove = onRemove
        return view
    }

    func updateNSView(_ nsView: FileDragNSView, context: Context) {
        nsView.url = url
        nsView.onHover = onHover
        nsView.onRemove = onRemove
    }
}

final class FileDragNSView: NSView, NSDraggingSource {
    var url: URL = URL(fileURLWithPath: "/")
    var onHover: (Bool) -> Void = { _ in }
    var onRemove: () -> Void = {}
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let reveal = menu.addItem(withTitle: L10n.tr("Show in Finder"), action: #selector(reveal), keyEquivalent: "")
        let remove = menu.addItem(withTitle: L10n.tr("Remove from Cloud"), action: #selector(removeFromCloud), keyEquivalent: "")
        reveal.target = self
        remove.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func removeFromCloud() {
        onRemove()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    override func mouseDown(with event: NSEvent) {
        let start = NSEvent.mouseLocation
        while true {
            guard let next = NSApp.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { return }

            if next.type == .leftMouseUp {
                if event.clickCount == 2 {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                return
            }

            let now = NSEvent.mouseLocation
            if hypot(now.x - start.x, now.y - start.y) > 4 {
                beginFileDrag(with: event)
                return
            }
        }
    }

    private func beginFileDrag(with event: NSEvent) {
        let writer = url as NSURL
        let item = NSDraggingItem(pasteboardWriter: writer)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 48, height: 48)
        let location = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(x: location.x - 24, y: location.y - 24, width: 48, height: 48),
            contents: icon
        )
        beginDraggingSession(with: [item], event: event, source: self)
    }
}
