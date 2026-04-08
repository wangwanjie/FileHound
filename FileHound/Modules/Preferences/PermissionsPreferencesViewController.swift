import AppKit

final class PermissionsPreferencesViewController: NSViewController {
    override func loadView() {
        view = PreferencesSectionView(title: "权限", subtitle: "Full Disk Access 与权限状态")
    }
}
