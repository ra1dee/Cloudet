import Foundation

enum FileName {
    static func sanitized(_ raw: String, fallback: String) -> String {
        var taken = Set<String>()
        return unique(raw, fallbackExtension: fallback, taken: &taken)
    }

    /// `fallbackExtension == nil` оставляет имя без расширения как есть.
    /// Так файл «README» не превращается в «README.png» при следующем запуске.
    static func unique(_ raw: String, fallbackExtension: String?, taken: inout Set<String>) -> String {
        var name = cleaned(raw)
        if name.isEmpty {
            name = "\(L10n.tr("Image")).\(fallbackExtension ?? "dat")"
        } else if let fallbackExtension, (name as NSString).pathExtension.isEmpty {
            name += ".\(fallbackExtension)"
        }
        if claim(name, taken: &taken) { return name }

        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var number = 2
        while number < 10_000 {
            let candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            if claim(candidate, taken: &taken) { return candidate }
            number += 1
        }
        let suffix = String(UUID().uuidString.prefix(4))
        let candidate = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
        taken.insert(candidate.lowercased())
        return candidate
    }

    static func cleaned(_ raw: String) -> String {
        var name = (raw as NSString).lastPathComponent
        name = String(name.unicodeScalars.filter { scalar in
            let value = scalar.value
            if value < 32 || value == 0x7F { return false }
            return scalar != "/" && scalar != ":" && scalar != "\\"
        })
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "." || name == ".." { return "" }
        if name.count > 180 {
            let ext = (name as NSString).pathExtension
            let stemBudget = ext.isEmpty ? 180 : max(1, 180 - ext.count - 1)
            let stem = String((name as NSString).deletingPathExtension.prefix(stemBudget))
            name = ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        return name
    }

    private static func claim(_ name: String, taken: inout Set<String>) -> Bool {
        let key = name.lowercased()
        if taken.contains(key) { return false }
        taken.insert(key)
        return true
    }
}

final class NameBag: @unchecked Sendable {
    private var taken: Set<String>

    init(existing: [String]) {
        taken = Set(existing.map { $0.lowercased() })
    }

    func claim(_ raw: String, fallbackExtension: String?) -> String {
        FileName.unique(raw, fallbackExtension: fallbackExtension, taken: &taken)
    }
}
