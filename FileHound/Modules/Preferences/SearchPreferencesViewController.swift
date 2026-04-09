import AppKit
import SnapKit

final class SearchPreferencesViewController: NSViewController {
    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.search.title"),
            subtitle: L10n.string("preferences.search.subtitle")
        )

        let expandFoldersButton = NSButton(checkboxWithTitle: "Expand all folders when showing results", target: nil, action: nil)
        let showResultsEarlyButton = NSButton(checkboxWithTitle: "Show Results Early", target: nil, action: nil)
        let includeSpotlightButton = NSButton(checkboxWithTitle: "Include Spotlight results", target: nil, action: nil)
        let specialFoldersButton = NSButton(title: "Special Folders…", target: nil, action: nil)

        let stack = NSStackView(views: [
            expandFoldersButton,
            showResultsEarlyButton,
            includeSpotlightButton,
            specialFoldersButton
        ])
        stack.orientation = .vertical
        stack.spacing = 14
        rootView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(rootView.contentGuide)
        }

        view = rootView
    }
}
