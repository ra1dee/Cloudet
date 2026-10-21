import AppKit

enum CloudShape {
    /// Силуэт срисован с cloud-filled из Tabler Icons (MIT, Paweł Kuna):
    /// одна непрерывная кривая, а не набор овалов.
    static func cgPath(in rect: CGRect) -> CGPath {
        outline(in: rect) { rect.minY + rect.height * $0 }
    }

    static func bezier(in rect: CGRect) -> NSBezierPath {
        let flipped = outline(in: rect) { rect.maxY - rect.height * $0 }
        return NSBezierPath(cgPath: flipped)
    }

    private static func outline(in rect: CGRect, y: (CGFloat) -> CGFloat) -> CGPath {
        let path = CGMutablePath()
        func q(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * nx, y: y(ny))
        }
        path.move(to: q(0.4109, 0.0434))
        path.addCurve(to: q(0.7000, 0.1199), control1: q(0.5107, 0.0000), control2: q(0.6207, 0.0288))
        path.addCurve(to: q(0.8024, 0.4024), control1: q(0.7630, 0.1920), control2: q(0.7995, 0.2947))
        path.addLine(to: q(0.8025, 0.4162))
        path.addLine(to: q(0.8066, 0.4164))
        path.addCurve(to: q(0.9998, 0.6943), control1: q(0.9112, 0.4233), control2: q(0.9950, 0.5440))
        path.addLine(to: q(1.0000, 0.7080))
        path.addCurve(to: q(0.8066, 0.9997), control1: q(1.0000, 0.8646), control2: q(0.9143, 0.9925))
        path.addLine(to: q(0.7970, 1.0000))
        path.addLine(to: q(0.2571, 1.0000))
        path.addLine(to: q(0.2470, 0.9995))
        path.addCurve(to: q(0.0002, 0.6570), control1: q(0.1134, 0.9923), control2: q(0.0054, 0.8434))
        path.addLine(to: q(0.0000, 0.6429))
        path.addCurve(to: q(0.2175, 0.2904), control1: q(0.0000, 0.4641), control2: q(0.0945, 0.3169))
        path.addLine(to: q(0.2226, 0.2893))
        path.addLine(to: q(0.2258, 0.2776))
        path.addCurve(to: q(0.3999, 0.0486), control1: q(0.2560, 0.1721), control2: q(0.3193, 0.0884))
        path.addLine(to: q(0.4110, 0.0434))
        path.closeSubpath()
        return path
    }
}

enum CloudIcon {
    static let aspect: CGFloat = 190.0 / 133.0

    static func menuImage() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            draw(in: rect, style: .menu)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "cloudet drag'n'drop"
        return image
    }

    static func drawAppIcon(in rect: CGRect) {
        draw(in: rect, style: .app)
    }

    private enum Style {
        case menu
        case app
    }

    private static func draw(in rect: CGRect, style: Style) {
        let inset = style == .menu ? 0.5 : rect.width * 0.12
        let path = cloudPath(in: rect, inset: inset)
        switch style {
        case .menu:
            NSColor.black.setFill()
            path.fill()
        case .app:
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSGradient(colors: [
                NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1),
                NSColor(srgbRed: 0.70, green: 0.72, blue: 0.76, alpha: 1)
            ])?.draw(in: path.bounds, angle: 90)
            NSGraphicsContext.restoreGraphicsState()
            path.lineJoinStyle = .round
            path.lineWidth = max(2, rect.width * 0.05)
            NSColor(srgbRed: 0.15, green: 0.15, blue: 0.17, alpha: 1).setStroke()
            path.stroke()
            path.lineWidth = max(1, rect.width * 0.024)
            NSColor.white.setStroke()
            path.stroke()
        }
    }

    private static func cloudPath(in rect: CGRect, inset: CGFloat) -> NSBezierPath {
        let box = rect.insetBy(dx: inset, dy: inset)
        let width = min(box.width, box.height * aspect)
        let height = width / aspect
        let cloud = CGRect(
            x: box.midX - width / 2,
            y: box.midY - height / 2,
            width: width,
            height: height
        )
        return CloudShape.bezier(in: cloud)
    }
}
