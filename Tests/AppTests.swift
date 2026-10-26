import Foundation

@main
enum AppTests {
    static func main() {
        var failed = false
        func expect(_ condition: Bool, _ message: String) {
            guard !condition else { return }
            failed = true
            fputs("FAIL \(message)\n", stderr)
        }

        var taken = Set<String>()
        expect(
            FileName.unique("Image.png", fallbackExtension: "png", taken: &taken) == "Image.png",
            "first image name"
        )
        expect(
            FileName.unique("Image.png", fallbackExtension: "png", taken: &taken) == "Image 2.png",
            "second image name"
        )
        expect(
            FileName.unique("Image.png", fallbackExtension: "png", taken: &taken) == "Image 3.png",
            "third image name"
        )
        expect(FileName.unique("README", fallbackExtension: nil, taken: &taken) == "README", "extensionless name")
        expect(FileName.cleaned("../") == "", "parent path")
        expect(
            ImageBytes.looksLikeImage(Data([0x89, 0x50, 0x4E, 0x47]), mime: "application/octet-stream"),
            "png magic"
        )
        expect(!ImageBytes.looksLikeImage(Data("<html></html>".utf8), mime: "text/html"), "html rejected")
        var heic = Data(repeating: 0, count: 12)
        for (offset, byte) in Array("ftypheic".utf8).enumerated() {
            heic[4 + offset] = byte
        }
        expect(ImageBytes.looksLikeImage(heic, mime: "application/octet-stream"), "heic brand")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloudet-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BufferStore(root: root)
        do {
            try store.prepare()
            let pack = root.appendingPathComponent("Pack", isDirectory: true)
            try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 5).write(to: pack.appendingPathComponent("a.bin"))
            try Data(repeating: 2, count: 7).write(to: pack.appendingPathComponent("b.bin"))
            let left = root.appendingPathComponent("left", isDirectory: true)
            let right = root.appendingPathComponent("right", isDirectory: true)
            try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
            try Data("a".utf8).write(to: left.appendingPathComponent("Note.txt"))
            try Data("b".utf8).write(to: right.appendingPathComponent("Note.txt"))
            try Data("readme".utf8).write(to: left.appendingPathComponent("README"))

            let session = store.makeSession()
            let folder = try store.importFile(from: pack, session: session)
            let first = try store.importFile(from: left.appendingPathComponent("Note.txt"), session: session)
            let second = try store.importFile(from: right.appendingPathComponent("Note.txt"), session: session)
            let readme = try store.importFile(from: left.appendingPathComponent("README"), session: session)
            expect(folder.kind == .folder, "folder kind \(folder.kind)")
            expect(folder.byteSize == 12, "folder size \(folder.byteSize)")
            expect(first.displayName == "Note.txt", "first note \(first.displayName)")
            expect(second.displayName == "Note 2.txt", "second note \(second.displayName)")
            expect(readme.displayName == "README", "readme \(readme.displayName)")

            try store.save([readme])
            let reloaded = BufferModel(store: store)
            expect(reloaded.files.map(\.displayName) == ["README"], "reloaded \(reloaded.files.map(\.displayName))")

            let brokenRoot = root.appendingPathComponent("broken", isDirectory: true)
            try FileManager.default.createDirectory(at: brokenRoot, withIntermediateDirectories: true)
            let brokenStore = BufferStore(root: brokenRoot)
            try brokenStore.prepare()
            let garbage = Data("{}".utf8)
            try garbage.write(to: brokenStore.indexURL)
            let broken = BufferModel(store: brokenStore)
            expect(broken.files.isEmpty, "corrupt index still listed files")
            expect(broken.lastError != nil, "corrupt index had no error")
            expect(try Data(contentsOf: brokenStore.indexURL) == garbage, "corrupt index was overwritten")
            expect(
                FileManager.default.fileExists(atPath: brokenRoot.appendingPathComponent("buffer.json.broken").path),
                "broken index was not copied aside"
            )
        } catch {
            expect(false, "threw \(error)")
        }

        let spotlight = KeyCombo(keyCode: 49, modifiers: .command)
        expect(ShortcutRules.isReserved(spotlight, system: [spotlight]), "spotlight conflict")
        expect(
            !ShortcutRules.isReserved(KeyCombo(keyCode: 8, modifiers: [.command, .option]), system: [spotlight]),
            "unrelated shortcut"
        )
        expect(ShortcutRules.isReserved(KeyCombo(keyCode: 48, modifiers: .command), system: []), "command-tab")
        expect(!ShortcutRules.hasChordModifier(.shift), "shift alone")
        expect(ShortcutRules.hasChordModifier([.command, .shift]), "command and shift")
        let system = SystemHotKeys.enabled()
        expect(!system.isEmpty, "system shortcuts were not read")
        if system.contains(spotlight) {
            expect(ShortcutRules.isReserved(spotlight, system: system), "enabled spotlight")
        }

        if failed {
            fputs("tests failed\n", stderr)
            exit(1)
        }
        print("tests passed")
    }
}
