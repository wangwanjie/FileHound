import AppKit

final class PermissionsPreferencesViewController: NSViewController {
    override func loadView() {
        view = PreferencesSectionView(
            title: L10n.string("preferences.permissions.title"),
            subtitle: L10n.string("preferences.permissions.subtitle")
        )
    }
}
