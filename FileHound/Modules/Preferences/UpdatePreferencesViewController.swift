import AppKit
import SnapKit

final class UpdatePreferencesViewController: NSViewController {
    private let updateButton = NSButton(title: L10n.string("preferences.update.check"), target: nil, action: nil)

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.update.title"),
            subtitle: L10n.string("preferences.update.subtitle")
        )

        updateButton.target = UpdateManager.shared
        updateButton.action = #selector(UpdateManager.checkForUpdates(_:))
        rootView.addSubview(updateButton)
        updateButton.snp.makeConstraints { make in
            make.leading.top.equalTo(rootView.contentGuide)
        }

        view = rootView
    }
}
