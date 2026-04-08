import AppKit

final class SearchPreferencesViewController: NSViewController {
    override func loadView() {
        view = PreferencesSectionView(title: "搜索", subtitle: "搜索范围与默认行为")
    }
}
