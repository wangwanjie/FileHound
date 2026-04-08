import AppKit

final class UpdatePreferencesViewController: NSViewController {
    override func loadView() {
        view = PreferencesSectionView(
            title: L10n.string("preferences.update.title"),
            subtitle: L10n.string("preferences.update.subtitle")
        )
    }
}
