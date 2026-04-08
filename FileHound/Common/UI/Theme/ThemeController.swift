import AppKit

final class ThemeController {
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
