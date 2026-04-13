import AppKit
import SnapKit

final class UpdatePreferencesViewController: NSViewController {
    private let settings: AppSettings
    private let updateManager: UpdateManager
    private let policyPopup = NSPopUpButton()
    private let autoDownloadButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let checkNowButton = NSButton(title: "", target: nil, action: nil)
    private let resetButton = NSButton(title: "", target: nil, action: nil)

    init(
        settings: AppSettings = .shared,
        updateManager: UpdateManager = .shared
    ) {
        self.settings = settings
        self.updateManager = updateManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.update.title"),
            subtitle: L10n.string("preferences.update.subtitle")
        )

        policyPopup.addItems(withTitles: UpdateCheckPolicy.menuTitles)
        policyPopup.setAccessibilityIdentifier("UpdatePolicyPopup")
        policyPopup.selectItem(at: selectedPolicyIndex())
        policyPopup.target = self
        policyPopup.action = #selector(policyChanged)

        autoDownloadButton.title = L10n.string("preferences.update.auto_download")
        autoDownloadButton.state = settings.autoDownloadUpdates ? .on : .off
        autoDownloadButton.target = self
        autoDownloadButton.action = #selector(autoDownloadChanged)

        checkNowButton.setAccessibilityIdentifier("CheckNowButton")
        checkNowButton.title = L10n.string("preferences.update.check_now")
        checkNowButton.target = updateManager
        checkNowButton.action = #selector(UpdateManager.checkForUpdates(_:))
        checkNowButton.isEnabled = updateManager.canCheckForUpdates
        checkNowButton.toolTip = updateManager.unavailableReason

        resetButton.title = L10n.string("preferences.reset_defaults")
        resetButton.target = self
        resetButton.action = #selector(resetDefaults)

        let stack = NSStackView(views: [
            makePreferencesFormRow(title: L10n.string("preferences.update.check_policy"), control: policyPopup),
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
        settings.updateCheckPolicy = policies[policyPopup.indexOfSelectedItem]
    }

    @objc
    private func autoDownloadChanged() {
        settings.autoDownloadUpdates = autoDownloadButton.state == .on
    }

    @objc
    private func resetDefaults() {
        settings.updateCheckPolicy = .onLaunch
        settings.autoDownloadUpdates = false
        policyPopup.selectItem(at: 0)
        autoDownloadButton.state = .off
    }

    private func selectedPolicyIndex() -> Int {
        switch settings.updateCheckPolicy {
        case .onLaunch: return 0
        case .manualOnly: return 1
        case .dailyAutomatic: return 2
        }
    }
}

private extension UpdateCheckPolicy {
    static var menuTitles: [String] {
        let policies: [UpdateCheckPolicy] = [.onLaunch, .manualOnly, .dailyAutomatic]
        return policies.map(\.localizedTitle)
    }

    var localizedTitle: String {
        switch self {
        case .onLaunch:
            return L10n.string("preferences.update.policy.on_launch")
        case .manualOnly:
            return L10n.string("preferences.update.policy.manual_only")
        case .dailyAutomatic:
            return L10n.string("preferences.update.policy.daily_automatic")
        }
    }
}

#if DEBUG
extension UpdatePreferencesViewController {
    func debugTriggerResetDefaults() {
        resetDefaults()
    }

    var debugSelectedPolicyIndex: Int {
        policyPopup.indexOfSelectedItem
    }

    var debugAutoDownloadEnabled: Bool {
        autoDownloadButton.state == .on
    }
}
#endif
