import AppKit
import SnapKit

final class GeneralPreferencesViewController: NSViewController {
    private let settings: AppSettings
    private let launchShortcutController: LaunchShortcutControlling
    private let hotKeyField = ShortcutRecorderField()
    private let finderOnlyButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let globalButton = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let openRecentButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let restorePreviousSearchButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let tieResultsWindowButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let quitWhenClosedButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init(
        settings: AppSettings = .shared,
        launchShortcutController: LaunchShortcutControlling = LaunchShortcutController.shared
    ) {
        self.settings = settings
        self.launchShortcutController = launchShortcutController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.general.title"),
            subtitle: L10n.string("preferences.general.subtitle")
        )

        hotKeyField.placeholderString = L10n.string("preferences.general.hot_key.placeholder")
        hotKeyField.shortcut = KeyboardShortcut(serialized: settings.launchShortcut)
        hotKeyField.target = self
        hotKeyField.action = #selector(launchShortcutChanged)
        finderOnlyButton.title = L10n.string("preferences.general.activation.finder_only")
        globalButton.title = L10n.string("preferences.general.activation.global")
        openRecentButton.title = L10n.string("preferences.general.open_recent_search_menu")
        restorePreviousSearchButton.title = L10n.string("preferences.general.restore_previous_search")
        tieResultsWindowButton.title = L10n.string("preferences.general.tie_results_window")
        quitWhenClosedButton.title = L10n.string("preferences.general.quit_when_closed")

        finderOnlyButton.target = self
        finderOnlyButton.action = #selector(activationModeChanged)
        globalButton.target = self
        globalButton.action = #selector(activationModeChanged)
        switch settings.activationMode {
        case .finderOnly:
            finderOnlyButton.state = .on
        case .global:
            globalButton.state = .on
        }

        openRecentButton.state = settings.openRecentSearchMenu ? .on : .off
        openRecentButton.target = self
        openRecentButton.action = #selector(openRecentSearchChanged)

        restorePreviousSearchButton.state = settings.restorePreviousSearch ? .on : .off
        restorePreviousSearchButton.target = self
        restorePreviousSearchButton.action = #selector(restorePreviousSearchChanged)

        tieResultsWindowButton.state = settings.tieResultsWindowToFindWindow ? .on : .off
        tieResultsWindowButton.target = self
        tieResultsWindowButton.action = #selector(tieResultsWindowChanged)

        quitWhenClosedButton.state = settings.quitWhenAllWindowsAreClosed ? .on : .off
        quitWhenClosedButton.target = self
        quitWhenClosedButton.action = #selector(quitWhenClosedChanged)

        let rows = NSStackView(views: [
            makePreferencesFormRow(title: L10n.string("preferences.general.hot_key"), control: hotKeyField),
            finderOnlyButton,
            globalButton,
            openRecentButton,
            restorePreviousSearchButton,
            tieResultsWindowButton,
            quitWhenClosedButton
        ])
        rows.orientation = .vertical
        rows.spacing = 14
        rows.alignment = .leading

        hotKeyField.snp.makeConstraints { make in
            make.width.equalTo(190)
            make.height.equalTo(32)
        }

        rootView.addSubview(rows)
        rows.snp.makeConstraints { make in
            make.edges.equalTo(rootView.contentGuide)
        }

        view = rootView
    }

    @objc
    private func launchShortcutChanged() {
        settings.launchShortcut = hotKeyField.shortcut?.serialized ?? ""
        launchShortcutController.reload()
    }

    @objc
    private func activationModeChanged(_ sender: NSButton) {
        settings.activationMode = sender === finderOnlyButton ? .finderOnly : .global
        launchShortcutController.reload()
    }

    @objc
    private func openRecentSearchChanged() {
        settings.openRecentSearchMenu = openRecentButton.state == .on
        NSApp.mainMenu = MainMenuBuilder(target: NSApp.delegate as AnyObject, settings: settings).build()
    }

    @objc
    private func restorePreviousSearchChanged() {
        settings.restorePreviousSearch = restorePreviousSearchButton.state == .on
    }

    @objc
    private func tieResultsWindowChanged() {
        settings.tieResultsWindowToFindWindow = tieResultsWindowButton.state == .on
    }

    @objc
    private func quitWhenClosedChanged() {
        settings.quitWhenAllWindowsAreClosed = quitWhenClosedButton.state == .on
    }
}

#if DEBUG
extension GeneralPreferencesViewController {
    func debugRecordShortcut(_ shortcut: KeyboardShortcut) {
        hotKeyField.shortcut = shortcut
        launchShortcutChanged()
    }

    var debugDisplayedLaunchShortcut: String {
        hotKeyField.debugDisplayedString
    }

    var debugHotKeyControlHeight: CGFloat {
        hotKeyField.fittingSize.height
    }
}
#endif
