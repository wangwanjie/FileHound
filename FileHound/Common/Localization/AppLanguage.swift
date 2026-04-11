enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en

    var displayName: String {
        switch self {
        case .system:
            return L10n.string("preferences.appearance.language.system")
        case .zhHans:
            return L10n.string("preferences.appearance.language.zh_hans")
        case .zhHant:
            return L10n.string("preferences.appearance.language.zh_hant")
        case .en:
            return L10n.string("preferences.appearance.language.en")
        }
    }
}
