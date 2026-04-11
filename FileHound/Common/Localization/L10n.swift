import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        LocalizationController.shared.localizedString(key)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}
