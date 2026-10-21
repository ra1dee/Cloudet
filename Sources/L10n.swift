import Foundation

enum L10n {
    static func tr(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: args)
    }

    static func files(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("files.count", comment: "How many files are in the cloud"),
            count
        )
    }

    static func more(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("more.count", comment: "How many further files are not named"),
            count
        )
    }
}
