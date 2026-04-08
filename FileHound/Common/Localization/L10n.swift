import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        LocalizationController.shared.localizedString(key)
    }
}
