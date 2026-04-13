import AppKit
import SnapKit

final class SearchPreferencesViewController: NSViewController {
    private let settings: AppSettings
    private let specialFoldersStore: SpecialFoldersStore
    private let expandFoldersButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let showResultsEarlyButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let includeSpotlightButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let specialFoldersButton = NSButton(title: "", target: nil, action: nil)
    private var specialFoldersWindowController: SpecialFoldersWindowController?

    init(
        settings: AppSettings = .shared,
        specialFoldersStore: SpecialFoldersStore = .shared
    ) {
        self.settings = settings
        self.specialFoldersStore = specialFoldersStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.search.title"),
            subtitle: L10n.string("preferences.search.subtitle")
        )

        expandFoldersButton.title = L10n.string("preferences.search.expand_folders")
        expandFoldersButton.state = settings.expandFoldersWhenShowingResults ? .on : .off
        expandFoldersButton.setAccessibilityIdentifier("SearchPreferenceExpandFoldersButton")
        expandFoldersButton.target = self
        expandFoldersButton.action = #selector(expandFoldersChanged)
        showResultsEarlyButton.title = L10n.string("preferences.search.show_results_early")
        showResultsEarlyButton.state = settings.showResultsEarly ? .on : .off
        showResultsEarlyButton.setAccessibilityIdentifier("SearchPreferenceShowResultsEarlyButton")
        showResultsEarlyButton.target = self
        showResultsEarlyButton.action = #selector(showResultsEarlyChanged)
        includeSpotlightButton.title = L10n.string("preferences.search.include_spotlight")
        includeSpotlightButton.state = settings.includeSpotlightResults ? .on : .off
        includeSpotlightButton.setAccessibilityIdentifier("SearchPreferenceIncludeSpotlightButton")
        includeSpotlightButton.target = self
        includeSpotlightButton.action = #selector(includeSpotlightChanged)
        specialFoldersButton.title = L10n.string("preferences.search.special_folders")
        specialFoldersButton.setAccessibilityIdentifier("SearchPreferenceSpecialFoldersButton")
        specialFoldersButton.target = self
        specialFoldersButton.action = #selector(openSpecialFolders)

        let stack = NSStackView(views: [
            expandFoldersButton,
            showResultsEarlyButton,
            includeSpotlightButton,
            specialFoldersButton
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
    private func expandFoldersChanged() {
        settings.expandFoldersWhenShowingResults = expandFoldersButton.state == .on
    }

    @objc
    private func showResultsEarlyChanged() {
        settings.showResultsEarly = showResultsEarlyButton.state == .on
    }

    @objc
    private func includeSpotlightChanged() {
        settings.includeSpotlightResults = includeSpotlightButton.state == .on
    }

    @objc
    private func openSpecialFolders() {
        let controller = specialFoldersWindowController ?? SpecialFoldersWindowController(store: specialFoldersStore)
        specialFoldersWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
