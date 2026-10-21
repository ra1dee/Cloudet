import AppKit
import ObjectiveC

enum LiquidGlass {
    static func effect(radius: CGFloat, interactive: Bool) -> NSView {
        guard let cls = NSClassFromString("NSGlassEffectView") as? NSView.Type else {
            let fallback = NSVisualEffectView()
            fallback.material = .hudWindow
            fallback.blendingMode = .behindWindow
            fallback.state = .active
            fallback.wantsLayer = true
            fallback.layer?.cornerRadius = radius
            fallback.layer?.masksToBounds = true
            return fallback
        }
        let view = cls.init(frame: .zero)
        view.setValue(0, forKey: "style")
        view.setValue(radius, forKey: "cornerRadius")
        view.setValue(interactive, forKey: "effectIsInteractive")
        return view
    }

    static func container(spacing: CGFloat) -> NSView {
        guard let cls = NSClassFromString("NSGlassEffectContainerView") as? NSView.Type else {
            return NSView()
        }
        let view = cls.init(frame: .zero)
        view.setValue(spacing, forKey: "spacing")
        return view
    }

    static func embed(_ content: NSView, in glass: NSView) {
        if glass.responds(to: NSSelectorFromString("setContentView:")) {
            glass.setValue(content, forKey: "contentView")
        } else {
            content.frame = glass.bounds
            content.autoresizingMask = [.width, .height]
            glass.addSubview(content)
        }
    }

    static func place(_ content: NSView, in container: NSView) {
        if container.responds(to: NSSelectorFromString("setContentView:")) {
            container.setValue(content, forKey: "contentView")
        } else {
            content.frame = container.bounds
            content.autoresizingMask = [.width, .height]
            container.addSubview(content)
        }
    }

    static func contentView(of glass: NSView) -> NSView? {
        glass.value(forKey: "contentView") as? NSView
    }

    /// Стекло в SDK нет, форма задаётся тем же приватным методом, которым
    /// пользуется само стекло. Без него материал остаётся прямоугольником.
    static func setPath(_ path: CGPath, on view: NSView) {
        let sel = NSSelectorFromString("_setPath:")
        guard let method = class_getInstanceMethod(type(of: view), sel) else { return }
        typealias SetPath = @convention(c) (AnyObject, Selector, CGPath) -> Void
        let setPath = unsafeBitCast(method_getImplementation(method), to: SetPath.self)
        setPath(view, sel, path)
    }
}
