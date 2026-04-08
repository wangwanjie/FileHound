import AppKit

final class UpdatePreferencesViewController: NSViewController {
    override func loadView() {
        view = PreferencesSectionView(title: "更新", subtitle: "自动更新与版本检查")
    }
}
