import AppKit

final class SearchRulesViewController: NSViewController {
    private let listView = SearchRuleListView()
    private var rows: [SearchRuleRowView] = []
    var onContentLayoutChange: ((CGFloat) -> Void)?

    override func loadView() {
        view = listView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addRow()
    }

    var currentSelection: SearchRuleSelection {
        rows.first?.selection ?? SearchRuleSelection()
    }

    var currentSelections: [SearchRuleSelection] {
        rows.map(\.selection)
    }

    func setEnabled(_ enabled: Bool) {
        rows.forEach { $0.setEnabled(enabled) }
    }

    var preferredContentHeight: CGFloat {
        listView.preferredContentHeight
    }

    func setScrollingEnabled(_ enabled: Bool) {
        listView.setScrollingEnabled(enabled)
    }

    private func addRow(after sourceRow: SearchRuleRowView? = nil) {
        let row = SearchRuleRowView()
        row.onAdd = { [weak self, weak row] in
            self?.addRow(after: row)
        }
        row.onRemove = { [weak self, weak row] in
            self?.removeRow(row)
        }

        let insertionIndex = sourceRow.flatMap { rows.firstIndex(of: $0).map { $0 + 1 } } ?? rows.count
        rows.insert(row, at: insertionIndex)
        listView.stackView.insertArrangedSubview(row, at: insertionIndex)
        updateRowControls()
        notifyContentLayoutChange()
    }

    private func removeRow(_ row: SearchRuleRowView?) {
        guard rows.count > 1, let row, let index = rows.firstIndex(of: row) else {
            return
        }

        rows.remove(at: index)
        listView.stackView.removeArrangedSubview(row)
        row.removeFromSuperview()
        updateRowControls()
        notifyContentLayoutChange()
    }

    private func updateRowControls() {
        let canRemove = rows.count > 1
        rows.forEach { $0.setRemoveEnabled(canRemove) }
    }

    private func notifyContentLayoutChange() {
        view.layoutSubtreeIfNeeded()
        onContentLayoutChange?(preferredContentHeight)
    }
}
