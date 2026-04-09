import AppKit
import SnapKit

final class ResultsToolbarView: NSView {
    let gridButton = NSButton(title: "Grid", target: nil, action: nil)
    let tableButton = NSButton(title: "Table", target: nil, action: nil)
    let treeButton = NSButton(title: "Tree", target: nil, action: nil)
    let invisiblesButton = NSButton(checkboxWithTitle: "Invisibles", target: nil, action: nil)
    let packageButton = NSButton(checkboxWithTitle: "Package Contents", target: nil, action: nil)
    let trashedButton = NSButton(checkboxWithTitle: "Trashed", target: nil, action: nil)
    let filterField = NSSearchField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        gridButton.setAccessibilityIdentifier("ResultsModeGridButton")
        tableButton.setAccessibilityIdentifier("ResultsModeTableButton")
        treeButton.setAccessibilityIdentifier("ResultsModeTreeButton")
        filterField.setAccessibilityIdentifier("ResultsFilterField")

        let stack = NSStackView(views: [
            gridButton,
            tableButton,
            treeButton,
            invisiblesButton,
            packageButton,
            trashedButton,
            NSView(),
            filterField
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12

        addSubview(stack)

        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(12)
        }

        filterField.snp.makeConstraints { make in
            make.width.equalTo(220)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
