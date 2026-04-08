import AppKit
import SnapKit

final class PermissionsPreferencesViewController: NSViewController {
    private let coordinator = PermissionGuidanceCoordinator()
    private let summaryLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.permissions.title"),
            subtitle: L10n.string("preferences.permissions.subtitle")
        )

        let state = coordinator.currentState()
        summaryLabel.stringValue = state.summary
        summaryLabel.textColor = state.bannerStyle == .warning ? .systemOrange : .secondaryLabelColor

        rootView.addSubview(summaryLabel)
        summaryLabel.snp.makeConstraints { make in
            make.leading.top.equalTo(rootView.contentGuide)
            make.trailing.equalToSuperview()
        }

        view = rootView
    }
}
