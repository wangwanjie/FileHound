import AppKit

final class AppearancePreferencesViewController: NSViewController {
    override func loadView() {
        view = PreferencesSectionView(title: "外观", subtitle: "主题与外观偏好")
    }
}
