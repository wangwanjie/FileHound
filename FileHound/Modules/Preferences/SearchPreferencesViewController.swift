import AppKit

final class SearchPreferencesViewController: NSViewController {
    override func loadView() {
        view = PreferencesSectionView(
            title: L10n.string("preferences.search.title"),
            subtitle: L10n.string("preferences.search.subtitle")
        )
    }
}
