import AppKit

final class SearchRulesViewController: NSViewController {
    private let listView = SearchRuleListView()
    private var rows: [SearchRuleRowView] = []
    private let validator = SearchRuleValidator()
    var onContentLayoutChange: ((CGFloat) -> Void)?
    var onSelectionsChange: (([SearchRuleSelection]) -> Void)?

    override func loadView() {
        view = listView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addRow()
        updateLogicSummary()
    }

    var currentSelection: SearchRuleSelection {
        rows.first?.selection ?? SearchRuleSelection()
    }

    var currentSelections: [SearchRuleSelection] {
        rows.map(\.selection)
    }

    var validationSummary: SearchRuleValidationSummary {
        let results = rows.map { validator.validate($0.selection) }
        let firstBlockingMessage = results.compactMap(\.blockingMessage).first
        return SearchRuleValidationSummary(
            canSearch: firstBlockingMessage == nil,
            firstBlockingMessage: firstBlockingMessage
        )
    }

    func applySelections(_ selections: [SearchRuleSelection]) {
        let normalizedSelections = selections.isEmpty ? [SearchRuleSelection()] : selections

        while rows.count < normalizedSelections.count {
            addRow()
        }

        while rows.count > normalizedSelections.count, let lastRow = rows.last {
            removeRow(lastRow)
        }

        for (row, selection) in zip(rows, normalizedSelections) {
            row.apply(selection: selection)
        }

        updateRowValidations()
        updateRowControls()
        updateLogicSummary()
        notifyContentLayoutChange()
        onSelectionsChange?(currentSelections)
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

    func reloadLocalizedStrings() {
        rows.forEach { $0.reloadLocalizedStrings() }
        updateRowValidations()
        updateLogicSummary()
    }

    private func addRow(after sourceRow: SearchRuleRowView? = nil) {
        let row = SearchRuleRowView()
        row.onAdd = { [weak self, weak row] in
            self?.addRow(after: row)
        }
        row.onRemove = { [weak self, weak row] in
            self?.removeRow(row)
        }
        row.onChange = { [weak self] in
            self?.handleRowChange()
        }

        let insertionIndex = sourceRow.flatMap { rows.firstIndex(of: $0).map { $0 + 1 } } ?? rows.count
        rows.insert(row, at: insertionIndex)
        listView.stackView.insertArrangedSubview(row, at: insertionIndex)
        updateRowValidations()
        updateRowControls()
        updateLogicSummary()
        notifyContentLayoutChange()
        onSelectionsChange?(currentSelections)
    }

    private func removeRow(_ row: SearchRuleRowView?) {
        guard rows.count > 1, let row, let index = rows.firstIndex(of: row) else {
            return
        }

        rows.remove(at: index)
        listView.stackView.removeArrangedSubview(row)
        row.removeFromSuperview()
        updateRowValidations()
        updateRowControls()
        updateLogicSummary()
        notifyContentLayoutChange()
        onSelectionsChange?(currentSelections)
    }

    private func updateRowControls() {
        let canRemove = rows.count > 1
        rows.forEach { $0.setRemoveEnabled(canRemove) }
    }

    private func handleRowChange() {
        updateRowValidations()
        updateLogicSummary()
        onSelectionsChange?(currentSelections)
    }

    private func updateLogicSummary() {
        let selections = currentSelections.isEmpty ? [SearchRuleSelection()] : currentSelections
        let summary = selections.map(\.summaryText).joined(separator: L10n.string("search_rule.summary.and_separator"))
        listView.updateLogicSummary(summary)
    }

    private func notifyContentLayoutChange() {
        view.layoutSubtreeIfNeeded()
        onContentLayoutChange?(preferredContentHeight)
    }

    private func updateRowValidations() {
        rows.forEach { row in
            row.applyValidation(validator.validate(row.selection))
        }
    }
}

#if DEBUG
extension SearchRulesViewController {
    var debugLogicSummary: String {
        listView.logicSummary
    }

    var debugCanSearch: Bool {
        validationSummary.canSearch
    }

    var debugBlockingMessage: String? {
        validationSummary.firstBlockingMessage
    }
}
#endif
