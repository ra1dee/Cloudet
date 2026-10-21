import AppKit

@main
enum MakeIcon {
    static func main() {
        let destination = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "Resources/AppIcon.icns"
        let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cloudet.iconset")
        let files = FileManager.default
        try? files.removeItem(at: iconset)
        try? files.createDirectory(at: iconset, withIntermediateDirectories: true)

        let sizes: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]
        for (name, pixels) in sizes {
            let png = render(pixels: pixels)
            try? png.write(to: iconset.appendingPathComponent(name))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", destination]
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            fputs("iconutil failed\n", stderr)
            exit(1)
        }

        try? render(pixels: 256).write(to: URL(fileURLWithPath: "/tmp/cloudet-appicon.png"))
        try? render(pixels: 72, menu: true).write(to: URL(fileURLWithPath: "/tmp/cloudet-menu.png"))
        print(destination)
    }

    private static func render(pixels: Int, menu: Bool = false) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        if menu {
            let image = CloudIcon.menuImage()
            image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        } else {
            CloudIcon.drawAppIcon(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
