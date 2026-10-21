import AppKit
import UniformTypeIdentifiers

struct ImagePayload {
    var promises: [NSFilePromiseReceiver] = []
    var files: [(name: String, data: Data)] = []
    var remoteURLs: [URL] = []

    var isEmpty: Bool { promises.isEmpty && files.isEmpty && remoteURLs.isEmpty }
}

enum ImageDrop {
    static var pasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = imageTypes + [.fileURL, .URL, .string]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        return types
    }

    static func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.availableType(from: imageTypes) != nil { return true }
        if !imagePromises(from: pasteboard).isEmpty { return true }
        if !remoteImageURLs(from: pasteboard).isEmpty { return true }
        return false
    }

    static func payload(from pasteboard: NSPasteboard) -> ImagePayload {
        var payload = ImagePayload()
        payload.promises = imagePromises(from: pasteboard)
        payload.files = inlineImages(from: pasteboard)
        payload.remoteURLs = remoteImageURLs(from: pasteboard)
        return payload
    }

    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.jpg"),
        NSPasteboard.PasteboardType("public.gif"),
        NSPasteboard.PasteboardType("public.webp"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("public.heif"),
        NSPasteboard.PasteboardType("com.microsoft.bmp"),
        NSPasteboard.PasteboardType("public.svg-image"),
        .tiff
    ]

    private static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif", "svg", "jfif", "ico"
    ]

    private static func isImageType(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .image)
    }

    private static func imagePromises(from pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver] ?? []
        let hasBitmap = pasteboard.availableType(from: imageTypes) != nil
        return receivers.filter { receiver in
            if receiver.fileTypes.contains(where: isImageType) { return true }
            return receiver.fileTypes.isEmpty && hasBitmap
        }
    }

    private static func inlineImages(from pasteboard: NSPasteboard) -> [(name: String, data: Data)] {
        let items = pasteboard.pasteboardItems ?? []
        var images: [(name: String, data: Data)] = []
        if items.isEmpty {
            if let image = firstImage(in: pasteboard, nameHint: nil, index: 1) {
                images.append(image)
            }
            return images
        }
        for (index, item) in items.enumerated() {
            if let image = firstImage(on: item, index: index + 1) {
                images.append(image)
            }
        }
        if images.isEmpty {
            let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] ?? []
            for (index, image) in objects.enumerated() {
                if let data = pngData(from: image) {
                    images.append((numberedName(extension: "png", index: index + 1), data))
                }
            }
        }
        return images
    }

    private static func firstImage(in pasteboard: NSPasteboard, nameHint: String?, index: Int) -> (name: String, data: Data)? {
        for type in imageTypes {
            guard let data = pasteboard.data(forType: type), !data.isEmpty else { continue }
            return storedImage(data: data, type: type, hint: nameHint, index: index)
        }
        return nil
    }

    private static func firstImage(on item: NSPasteboardItem, index: Int) -> (name: String, data: Data)? {
        let hint = fileNameHint(on: item)
        for type in imageTypes {
            guard let data = item.data(forType: type), !data.isEmpty else { continue }
            return storedImage(data: data, type: type, hint: hint, index: index)
        }
        return nil
    }

    private static func storedImage(
        data: Data,
        type: NSPasteboard.PasteboardType,
        hint: String?,
        index: Int
    ) -> (name: String, data: Data) {
        var ext = fileExtension(for: type)
        var bytes = data
        if ext == "tiff", let png = pngData(fromTIFF: data) {
            ext = "png"
            bytes = png
        }
        let name = hint.flatMap { named($0, fallbackExtension: ext) } ?? numberedName(extension: ext, index: index)
        return (name, bytes)
    }

    private static func fileNameHint(on item: NSPasteboardItem) -> String? {
        if let file = item.string(forType: .fileURL).flatMap(URL.init(string:))?.lastPathComponent, !file.isEmpty {
            return file
        }
        if let text = item.string(forType: .URL), let url = URL(string: text) {
            let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
            if extensions.contains(url.pathExtension.lowercased()), !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private static func remoteImageURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: false]
        ) as? [URL] ?? []
        let web = objects.filter { $0.scheme == "http" || $0.scheme == "https" }
        let named = web.filter { extensions.contains($0.pathExtension.lowercased()) }
        if !named.isEmpty { return named }
        if pasteboard.availableType(from: imageTypes) != nil, web.count == 1 {
            return web
        }
        if web.isEmpty, let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: text),
           url.scheme == "http" || url.scheme == "https",
           extensions.contains(url.pathExtension.lowercased()) {
            return [url]
        }
        return []
    }

    private static func fileExtension(for type: NSPasteboard.PasteboardType) -> String {
        switch type.rawValue {
        case "public.jpeg", "public.jpg": return "jpg"
        case "public.gif": return "gif"
        case "public.webp": return "webp"
        case "public.heic", "public.heif": return "heic"
        case "com.microsoft.bmp": return "bmp"
        case "public.svg-image": return "svg"
        case "public.tiff", NSPasteboard.PasteboardType.tiff.rawValue: return "tiff"
        default: return "png"
        }
    }

    private static func numberedName(extension ext: String, index: Int) -> String {
        let base = L10n.tr("Image")
        if index <= 1 { return "\(base).\(ext)" }
        return "\(base) \(index).\(ext)"
    }

    private static func named(_ raw: String, fallbackExtension: String) -> String? {
        let cleaned = FileName.sanitized(raw, fallback: fallbackExtension)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func pngData(fromTIFF data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return pngData(fromTIFF: tiff)
    }
}

enum ImageBytes {
    static func looksLikeImage(_ data: Data, mime: String) -> Bool {
        let mime = mime.lowercased()
        if mime.hasPrefix("text/html") || mime.contains("html") { return false }
        if mime.hasPrefix("image/") { return true }
        if data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) { return true }
        if data.starts(with: Data([0xFF, 0xD8, 0xFF])) { return true }
        if data.starts(with: Data([0x47, 0x49, 0x46, 0x38])) { return true }
        if data.count >= 12,
           String(data: data.prefix(4), encoding: .ascii) == "RIFF",
           String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WEBP" {
            return true
        }
        if data.starts(with: Data([0x49, 0x49, 0x2A, 0x00])) || data.starts(with: Data([0x4D, 0x4D, 0x00, 0x2A])) {
            return true
        }
        if isContainerImage(data) { return true }
        if data.prefix(512).contains(where: { $0 == UInt8(ascii: "<") }) {
            let head = String(data: data.prefix(512), encoding: .utf8)?.lowercased() ?? ""
            if head.contains("<svg") { return true }
        }
        return false
    }

    private static func isContainerImage(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        guard String(data: data.subdata(in: 4..<8), encoding: .ascii) == "ftyp" else { return false }
        let brand = String(data: data.subdata(in: 8..<12), encoding: .ascii)?.lowercased() ?? ""
        return ["heic", "heix", "heif", "mif1", "avif", "avis", "hevc"].contains(brand)
    }
}

enum ImageFetch {
    static let byteLimit = 80 * 1024 * 1024

    static func download(_ url: URL) throws -> (name: String, data: Data) {
        guard url.scheme == "http" || url.scheme == "https" else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let semaphore = DispatchSemaphore(value: 0)
        var body: Data?
        var response: URLResponse?
        var failure: Error?
        let task = URLSession.shared.dataTask(with: request) { data, resp, error in
            body = data
            response = resp
            failure = error
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 30) == .timedOut {
            task.cancel()
            throw URLError(.timedOut)
        }
        if let failure { throw failure }
        guard let body, !body.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        if body.count > byteLimit { throw CocoaError(.fileReadTooLarge) }
        let http = response as? HTTPURLResponse
        if let status = http?.statusCode, !(200..<300).contains(status) {
            throw CocoaError(.fileReadUnknown)
        }
        let mime = http?.mimeType?.lowercased() ?? ""
        if !ImageBytes.looksLikeImage(body, mime: mime) {
            throw CocoaError(.fileReadCorruptFile)
        }
        let ext = extensionFor(mime: mime, data: body, url: url)
        let hinted = url.lastPathComponent.removingPercentEncoding ?? ""
        let name = FileName.sanitized(hinted.isEmpty ? "\(L10n.tr("Image")).\(ext)" : hinted, fallback: ext)
        return (name, body)
    }

    private static func extensionFor(mime: String, data: Data, url: URL) -> String {
        switch mime {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic", "image/heif": return "heic"
        case "image/tiff": return "tiff"
        case "image/bmp": return "bmp"
        case "image/svg+xml": return "svg"
        case "image/avif": return "avif"
        default:
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty { return ext == "jpeg" ? "jpg" : ext }
            if data.starts(with: Data([0xFF, 0xD8, 0xFF])) { return "jpg" }
            if data.starts(with: Data([0x47, 0x49, 0x46, 0x38])) { return "gif" }
            return "png"
        }
    }
}
