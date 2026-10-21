import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum Chrome {
    static let cloud = NSSize(width: 190, height: 133)
    static let collapsed = NSSize(width: 222, height: 174)
    static let expandedWidth: CGFloat = 320
    static let topInset: CGFloat = 18
    static let gap: CGFloat = 8
    static let bottomInset: CGFloat = 14
    static let sideInset: CGFloat = 14
    static let row: CGFloat = 44
    static let maxRows = 6
    static let shelfRadius: CGFloat = 26

    static func shelfHeight(files: Int, hasError: Bool) -> CGFloat {
        let error: CGFloat = hasError ? 36 : 0
        if files == 0 { return 108 + error }
        let rows = min(files, maxRows)
        return 68 + CGFloat(rows) * row + error
    }

    static func expandedSize(files: Int, hasError: Bool) -> NSSize {
        let height = topInset + cloud.height + gap + shelfHeight(files: files, hasError: hasError) + bottomInset
        return NSSize(width: expandedWidth, height: height)
    }
}

struct CloudLabel: View {
    @ObservedObject var model: BufferModel

    private var names: [String] {
        model.files.prefix(2).map(\.displayName)
    }

    private var extra: Int {
        max(0, model.files.count - names.count)
    }

    var body: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if extra > 0 {
                Text(L10n.more(extra))
                    .foregroundStyle(.secondary)
            }
            Spacer().frame(height: 26)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(model.files.isEmpty ? 0 : 1)
        .background(Color.clear)
    }
}

struct Shelf: View {
    @ObservedObject var model: BufferModel

    private var rowCount: Int { min(model.files.count, Chrome.maxRows) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.files.isEmpty {
                header
                hairline
            }
            if let error = model.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
            if model.files.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.files) { file in
                            FileRow(file: file, url: model.store.url(for: file)) {
                                model.remove(file)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollIndicators(.automatic)
                .frame(height: CGFloat(rowCount) * Chrome.row)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: model.files.isEmpty ? .center : .top
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(L10n.files(model.files.count))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if model.files.count > 1 {
                Text(model.totalSizeText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                model.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("Remove copies from the cloud. Originals stay where they are."))
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text(L10n.tr("Drop files"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Text(L10n.tr("A copy stays here"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct FileRow: View {
    let file: BufferedFile
    let url: URL
    var onRemove: () -> Void

    @State private var hovered = false
    @State private var preview: NSImage?

    init(file: BufferedFile, url: URL, onRemove: @escaping () -> Void) {
        self.file = file
        self.url = url
        self.onRemove = onRemove
        _preview = State(initialValue: Thumbnail.icon(for: url))
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 28, height: 28)
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(hovered ? L10n.tr("Drag to copy") : file.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .allowsHitTesting(false)
            Spacer(minLength: 4)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.primary.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
            .help(L10n.tr("Remove from Cloud"))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Chrome.row)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.08 : 0))
                .allowsHitTesting(false)
        )
        .background(FileDragPad(url: url, onHover: { hovered = $0 }, onRemove: onRemove))
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(L10n.tr("Drag to copy. Double-click to show in Finder."))
        .task(id: url) {
            let current = url
            let box = await Task.detached(priority: .userInitiated) {
                PreviewBox(Thumbnail.pixels(at: current))
            }.value
            if let image = box.image, url == current {
                preview = image
            }
        }
    }
}

final class PreviewBox: @unchecked Sendable {
    let image: NSImage?
    init(_ image: NSImage?) { self.image = image }
}

enum Thumbnail {
    static func icon(for url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    static func pixels(at url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        guard
            let identifier = CGImageSourceGetType(source) as String?,
            UTType(identifier)?.conforms(to: .image) == true
        else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
