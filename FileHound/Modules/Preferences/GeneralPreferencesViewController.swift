import AppKit
import SnapKit

final class GeneralPreferencesViewController: NSViewController {
    private let hotKeyField = NSTextField()
    private let finderOnlyButton = NSButton(radioButtonWithTitle: "Works only in Finder", target: nil, action: nil)
    private let globalButton = NSButton(radioButtonWithTitle: "Works globally", target: nil, action: nil)
    private let openRecentButton = NSButton(checkboxWithTitle: "Enable \"Open Recent Search\" menu", target: nil, action: nil)
    private let quitWhenClosedButton = NSButton(checkboxWithTitle: "Quit when all windows are closed", target: nil, action: nil)

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: "General",
            subtitle: "General application behavior"
        )

        hotKeyField.placeholderString = "Click to set"
        hotKeyField.alignment = .left

        let rows = NSStackView(views: [
            makePreferencesFormRow(title: "Hot Key", control: hotKeyField),
            finderOnlyButton,
            globalButton,
            openRecentButton,
            quitWhenClosedButton
        ])
        rows.orientation = .vertical
        rows.spacing = 14
        rows.alignment = .leading

        rootView.addSubview(rows)
        rows.snp.makeConstraints { make in
            make.edges.equalTo(rootView.contentGuide)
        }

        view = rootView
    }
}
