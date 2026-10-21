import AppKit

enum ItemKind: String, Codable {
    case file
    case folder
    case package
}

struct BufferedFile: Identifiable, Codable, Equatable {
    let id: UUID
    let displayName: String
    let byteSize: Int64
    let kind: ItemKind
    let addedAt: Date

    var detail: String {
        switch kind {
        case .folder:
            return "\(L10n.tr("Folder")) · \(Formatters.bytes(byteSize))"
        case .package:
            return "\(L10n.tr("Package")) · \(Formatters.bytes(byteSize))"
        case .file:
            let ext = (displayName as NSString).pathExtension
            let size = Formatters.bytes(byteSize)
            guard !ext.isEmpty else { return size }
            return "\(ext.uppercased()) · \(size)"
        }
    }

    func with(name: String? = nil, byteSize: Int64? = nil) -> BufferedFile {
        BufferedFile(
            id: id,
            displayName: name ?? displayName,
            byteSize: byteSize ?? self.byteSize,
            kind: kind,
            addedAt: addedAt
        )
    }
}

enum Formatters {
    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: count)
    }
}

enum BufferError: LocalizedError {
    case unreadableIndex

    var errorDescription: String? {
        L10n.tr("Couldn’t read the cloud index.")
    }
}

enum StoredIndex {
    case missing
    case ready([BufferedFile])
    case unreadable
}

struct BufferStore: Sendable {
    let root: URL

    var indexURL: URL { root.appendingPathComponent("buffer.json") }
    var filesRoot: URL { root.appendingPathComponent("Files", isDirectory: true) }
    private var brokenIndexURL: URL { root.appendingPathComponent("buffer.json.broken") }

    static func live() -> BufferStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = support.appendingPathComponent("cloudet", isDirectory: true)
        let previous = support.appendingPathComponent("Whisp", isDirectory: true)
        let legacy = support.appendingPathComponent("DropyCopy", isDirectory: true)
        let files = FileManager.default
        if !files.fileExists(atPath: root.path) {
            if files.fileExists(atPath: previous.path) {
                try? files.moveItem(at: previous, to: root)
            } else if files.fileExists(atPath: legacy.path) {
                try? files.moveItem(at: legacy, to: root)
            }
        }
        return BufferStore(root: root)
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: filesRoot, withIntermediateDirectories: true)
    }

    func contains(_ url: URL) -> Bool {
        let prefix = filesRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == prefix || path.hasPrefix(prefix + "/")
    }

    func url(for file: BufferedFile) -> URL {
        filesRoot
            .appendingPathComponent(file.id.uuidString, isDirectory: true)
            .appendingPathComponent(file.displayName)
    }

    func readIndex() -> StoredIndex {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return .missing }
        guard
            let data = try? Data(contentsOf: indexURL),
            !data.isEmpty,
            let files = try? JSONDecoder().decode([BufferedFile].self, from: data)
        else {
            return .unreadable
        }
        let present = files.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
        return .ready(present)
    }

    /// Порченый список не затирается: копия остаётся рядом, пока индекс не починят.
    func quarantineIndex() {
        guard !FileManager.default.fileExists(atPath: brokenIndexURL.path) else { return }
        try? FileManager.default.copyItem(at: indexURL, to: brokenIndexURL)
    }

    func save(_ files: [BufferedFile]) throws {
        let data = try JSONEncoder().encode(files)
        try data.write(to: indexURL, options: .atomic)
    }

    func delete(_ file: BufferedFile) {
        let folder = filesRoot.appendingPathComponent(file.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    func makeSession() -> ImportSession {
        let existing: [BufferedFile]
        if case .ready(let files) = readIndex() {
            existing = files
        } else {
            existing = []
        }
        return ImportSession(files: existing)
    }

    func importFiles(from urls: [URL], session: ImportSession) -> (files: [BufferedFile], failure: String?) {
        var created: [BufferedFile] = []
        var failure: String?
        for url in urls {
            do {
                created.append(try importFile(from: url, session: session))
            } catch {
                failure = error.localizedDescription
            }
        }
        return (created, failure)
    }

    func importFile(from source: URL, session: ImportSession) throws -> BufferedFile {
        var coordinationError: NSError?
        var created: BufferedFile?
        var caught: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            do {
                created = try copyIn(url, session: session)
            } catch {
                caught = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let caught { throw caught }
        guard let created else { throw CocoaError(.fileReadUnknown) }
        return created
    }

    func importData(_ data: Data, preferredName: String, session: ImportSession) throws -> BufferedFile {
        guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let ext = (preferredName as NSString).pathExtension
        let name = session.names.claim(preferredName, fallbackExtension: ext.isEmpty ? "png" : ext)
        return try write(data, id: UUID(), name: name)
    }

    func importImages(
        files: [(name: String, data: Data)],
        remotes: [URL],
        session: ImportSession
    ) -> (files: [BufferedFile], failure: String?) {
        var created: [BufferedFile] = []
        var failure: String?
        for item in files {
            do {
                created.append(try importData(item.data, preferredName: item.name, session: session))
            } catch {
                failure = error.localizedDescription
            }
        }
        if created.isEmpty {
            for url in remotes {
                do {
                    let downloaded = try ImageFetch.download(url)
                    created.append(try importData(downloaded.data, preferredName: downloaded.name, session: session))
                } catch {
                    failure = error.localizedDescription
                }
            }
        }
        if created.isEmpty, failure == nil {
            failure = L10n.tr("That isn’t an image.")
        }
        return (created, failure)
    }

    /// Одинаковые имена становятся «Имя», «Имя 2», «Имя 3». Старые папки получают настоящий размер.
    func disambiguate(_ files: [BufferedFile]) -> [BufferedFile] {
        var taken = Set<String>()
        var renamed: [BufferedFile] = []
        for file in files.reversed() {
            let ext = (file.displayName as NSString).pathExtension
            let fallback: String? = ext.isEmpty ? nil : ext
            let name = FileName.unique(file.displayName, fallbackExtension: fallback, taken: &taken)
            var display = file.displayName
            if name != file.displayName {
                let current = url(for: file)
                let moved = current.deletingLastPathComponent().appendingPathComponent(name)
                if (try? FileManager.default.moveItem(at: current, to: moved)) != nil {
                    display = name
                }
            }
            var updated = file.with(name: display)
            if updated.kind != .file, let size = try? Storage.byteCount(at: url(for: updated)) {
                updated = updated.with(byteSize: size)
            }
            renamed.append(updated)
        }
        return Array(renamed.reversed())
    }

    private func copyIn(_ source: URL, session: ImportSession) throws -> BufferedFile {
        let ext = source.pathExtension
        let fallback: String? = ext.isEmpty ? nil : ext
        let name = session.names.claim(source.lastPathComponent, fallbackExtension: fallback)
        guard !name.isEmpty else { throw CocoaError(.fileReadInvalidFileName) }

        let id = UUID()
        let folder = try makeFolder(id)
        let destination = folder.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            Quarantine.remove(at: destination)
            let size = try Storage.byteCount(at: destination)
            return try describe(destination, id: id, name: name, byteSize: size)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func write(_ data: Data, id: UUID, name: String) throws -> BufferedFile {
        let folder = try makeFolder(id)
        let destination = folder.appendingPathComponent(name)
        do {
            try data.write(to: destination, options: .atomic)
            return try describe(destination, id: id, name: name, byteSize: Int64(data.count))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func makeFolder(_ id: UUID) throws -> URL {
        let folder = filesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func describe(_ destination: URL, id: UUID, name: String, byteSize: Int64) throws -> BufferedFile {
        let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isPackageKey])
        let kind: ItemKind
        if values.isSymbolicLink == true {
            kind = .file
        } else if values.isPackage == true {
            kind = .package
        } else if values.isDirectory == true {
            kind = .folder
        } else {
            kind = .file
        }
        return BufferedFile(id: id, displayName: name, byteSize: byteSize, kind: kind, addedAt: Date())
    }
}

final class ImportSession {
    let names: NameBag

    init(files: [BufferedFile]) {
        names = NameBag(existing: files.map(\.displayName))
    }
}

enum Storage {
    static func byteCount(at url: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        if values.isSymbolicLink == true || values.isDirectory != true {
            return Int64(values.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: []
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let itemValues = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if itemValues.isDirectory == true { continue }
            total += Int64(itemValues.fileSize ?? 0)
        }
        return total
    }
}

enum Quarantine {
    static func remove(at url: URL) {
        strip(url)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isSymbolicLink != true, values?.isDirectory == true else { return }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        for case let item as URL in enumerator {
            strip(item)
        }
    }

    private static func strip(_ url: URL) {
        removexattr(url.path, "com.apple.quarantine", 0)
    }
}

@MainActor
final class BufferModel: ObservableObject {
    @Published var files: [BufferedFile] = []
    @Published var expanded = false
    @Published var isDragTarget = false
    @Published var isCopying = false
    @Published var lastError: String?

    let store: BufferStore
    private let io = DispatchQueue(label: "cloudet.io", qos: .userInitiated)
    private var importsInFlight = 0

    init(store: BufferStore) {
        self.store = store
        do {
            try store.prepare()
        } catch {
            lastError = error.localizedDescription
            expanded = true
        }
        switch store.readIndex() {
        case .missing:
            files = []
        case .ready(let loaded):
            files = store.disambiguate(loaded)
            do {
                try store.save(files)
            } catch {
                lastError = error.localizedDescription
                expanded = true
            }
        case .unreadable:
            store.quarantineIndex()
            files = []
            lastError = BufferError.unreadableIndex.localizedDescription
            expanded = true
        }
    }

    var totalSizeText: String {
        Formatters.bytes(files.reduce(Int64(0)) { $0 + $1.byteSize })
    }

    var preferredSize: NSSize {
        guard expanded else { return Chrome.collapsed }
        return Chrome.expandedSize(files: files.count, hasError: lastError != nil)
    }

    func accept(urls: [URL]) {
        let incoming = urls.filter { !$0.path.isEmpty && !store.contains($0) }
        guard !incoming.isEmpty else { return }
        let scoped = incoming.filter { $0.startAccessingSecurityScopedResource() }
        beginImport()
        scheduleImport(urls: incoming, scoped: scoped, store: store, model: self, queue: io)
    }

    func acceptPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let payload = ImageDrop.payload(from: pasteboard)
        guard !payload.isEmpty else { return false }
        beginImport()
        scheduleImageImport(payload: payload, store: store, model: self, queue: io)
        return true
    }

    func remove(_ file: BufferedFile) {
        store.delete(file)
        files.removeAll { $0.id == file.id }
        try? store.save(files)
    }

    func clear() {
        for file in files {
            store.delete(file)
        }
        files = []
        lastError = nil
        try? store.save(files)
    }

    private func beginImport() {
        importsInFlight += 1
        isCopying = true
        lastError = nil
    }

    fileprivate func applyImport(created: [BufferedFile], failure: String?) {
        files.insert(contentsOf: created, at: 0)
        do {
            try store.save(files)
        } catch {
            lastError = error.localizedDescription
        }
        importsInFlight = max(0, importsInFlight - 1)
        isCopying = importsInFlight > 0
        if lastError == nil {
            if let failure, created.isEmpty {
                lastError = L10n.format("Couldn’t add: %@", failure)
            } else if let failure {
                lastError = L10n.format("Some files weren’t added: %@", failure)
            }
        }
        if !created.isEmpty || lastError != nil {
            expanded = true
        }
    }
}

/// Отдельные функции, а не замыкания внутри модели: swiftc 6.1 падает
/// в ClosureLifetimeFixup на вложенном захвате self.
private func scheduleImport(
    urls: [URL],
    scoped: [URL],
    store: BufferStore,
    model: BufferModel,
    queue: DispatchQueue
) {
    queue.async {
        defer {
            for url in scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let result = store.importFiles(from: urls, session: store.makeSession())
        DispatchQueue.main.sync {
            model.applyImport(created: result.files, failure: result.failure)
        }
    }
}

private final class ArrivalCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private final class PromisedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URL] = []

    func add(_ url: URL) {
        lock.lock()
        items.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

private func scheduleImageImport(
    payload: ImagePayload,
    store: BufferStore,
    model: BufferModel,
    queue: DispatchQueue
) {
    guard !payload.promises.isEmpty else {
        queue.async {
            let result = store.importImages(
                files: payload.files,
                remotes: payload.remoteURLs,
                session: store.makeSession()
            )
            DispatchQueue.main.sync {
                model.applyImport(created: result.files, failure: result.failure)
            }
        }
        return
    }

    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("cloudet-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let collected = PromisedURLs()
    let group = DispatchGroup()
    let readerQueue = OperationQueue()
    readerQueue.qualityOfService = .userInitiated
    for receiver in payload.promises {
        group.enter()
        let expected = max(receiver.fileNames.count, 1)
        let progress = ArrivalCount()
        receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: readerQueue) { url, error in
            if error == nil {
                collected.add(url)
            }
            if progress.next() == expected {
                group.leave()
            }
        }
    }

    DispatchQueue.global(qos: .userInitiated).async {
        _ = group.wait(timeout: .now() + 30)
        queue.async {
            let session = store.makeSession()
            var created: [BufferedFile] = []
            var failure: String?
            for url in collected.urls {
                do {
                    created.append(try store.importFile(from: url, session: session))
                } catch {
                    failure = error.localizedDescription
                }
            }
            try? FileManager.default.removeItem(at: destination)
            if created.isEmpty {
                let fallback = store.importImages(
                    files: payload.files,
                    remotes: payload.remoteURLs,
                    session: session
                )
                if !fallback.files.isEmpty {
                    created = fallback.files
                    failure = fallback.failure
                } else if failure == nil {
                    failure = fallback.failure
                }
            }
            let reported = failure
            let saved = created
            DispatchQueue.main.sync {
                model.applyImport(created: saved, failure: reported)
            }
        }
    }
}
