enum AppTheme: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system:
            return L10n.string("preferences.appearance.theme.system")
        case .light:
            return L10n.string("preferences.appearance.theme.light")
        case .dark:
            return L10n.string("preferences.appearance.theme.dark")
        }
    }
}
