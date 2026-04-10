import AppKit
import SnapKit

final class UpdatePreferencesViewController: NSViewController {
    private let policyPopup = NSPopUpButton()
    private let autoDownloadButton = NSButton(checkboxWithTitle: "Automatically download updates", target: nil, action: nil)
    private let checkNowButton = NSButton(title: "Check Now", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset to Defaults", target: nil, action: nil)

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.update.title"),
            subtitle: L10n.string("preferences.update.subtitle")
        )

        policyPopup.addItems(withTitles: ["On Launch", "Manual Only", "Daily Automatic"])
        policyPopup.setAccessibilityIdentifier("UpdatePolicyPopup")
        policyPopup.selectItem(at: selectedPolicyIndex())
        policyPopup.target = self
        policyPopup.action = #selector(policyChanged)

        autoDownloadButton.state = AppSettings.shared.autoDownloadUpdates ? .on : .off
        autoDownloadButton.target = self
        autoDownloadButton.action = #selector(autoDownloadChanged)

        checkNowButton.setAccessibilityIdentifier("CheckNowButton")
        checkNowButton.target = UpdateManager.shared
        checkNowButton.action = #selector(UpdateManager.checkForUpdates(_:))
        checkNowButton.isEnabled = UpdateManager.shared.canCheckForUpdates
        checkNowButton.toolTip = UpdateManager.shared.canCheckForUpdates ? nil : "Update feed is not configured in this build."

        resetButton.target = self
        resetButton.action = #selector(resetDefaults)

        let stack = NSStackView(views: [
            makePreferencesFormRow(title: "Check Policy", control: policyPopup),
            autoDownloadButton,
            checkNowButton,
            resetButton
        ])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .leading

        rootView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(rootView.contentGuide)
        }

        view = rootView
    }

    @objc
    private func policyChanged() {
        let policies: [UpdateCheckPolicy] = [.onLaunch, .manualOnly, .dailyAutomatic]
        AppSettings.shared.updateCheckPolicy = policies[policyPopup.indexOfSelectedItem]
    }

    @objc
    private func autoDownloadChanged() {
        AppSettings.shared.autoDownloadUpdates = autoDownloadButton.state == .on
    }

    @objc
    private func resetDefaults() {
        AppSettings.shared.updateCheckPolicy = .onLaunch
        AppSettings.shared.autoDownloadUpdates = false
        policyPopup.selectItem(at: 0)
        autoDownloadButton.state = .off
    }

    private func selectedPolicyIndex() -> Int {
        switch AppSettings.shared.updateCheckPolicy {
        case .onLaunch: return 0
        case .manualOnly: return 1
        case .dailyAutomatic: return 2
        }
    }
}
