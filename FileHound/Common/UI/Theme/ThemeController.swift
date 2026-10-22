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

    /// 主题对应的外观；跟随系统时为 nil（继承上级 / 系统外观）
    static func appearance(for theme: AppTheme) -> NSAppearance? {
        switch theme {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    /// 应用到单个窗口 / 视图（独立于 App 外观、需要单独跟随主题的窗口使用）
    func apply(theme: AppTheme, to target: NSAppearanceCustomization?) {
        target?.appearance = Self.appearance(for: theme)
    }

    /// 应用到整个 App：未单独设置外观的窗口，以及 NSAlert、NSOpenPanel 等系统面板都会继承
    func applyToApplication(theme: AppTheme, application: NSApplication? = NSApp) {
        apply(theme: theme, to: application)
    }
}
