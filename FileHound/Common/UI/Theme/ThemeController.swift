import AppKit
import Combine

final class ThemeController {
    static let shared = ThemeController(settings: .shared)

    private let settings: AppSettings
    private let subject: CurrentValueSubject<AppTheme, Never>

    var publisher: AnyPublisher<AppTheme, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentTheme: AppTheme {
        subject.value
    }

    init(settings: AppSettings) {
        self.settings = settings
        self.subject = CurrentValueSubject(settings.preferredTheme)
    }

    func select(theme: AppTheme) {
        settings.preferredTheme = theme
        subject.send(theme)
    }

    func apply(theme: AppTheme, to window: NSWindow?) {
        switch theme {
        case .system:
            window?.appearance = nil
        case .light:
            window?.appearance = NSAppearance(named: .aqua)
        case .dark:
            window?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
