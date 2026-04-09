import AppKit

final class SearchRulesViewController: NSViewController {
    private let listView = SearchRuleListView()
    private var rows: [SearchRuleRowView] = []

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

    func setEnabled(_ enabled: Bool) {
        rows.forEach { $0.setEnabled(enabled) }
    }

    private func addRow() {
        let row = SearchRuleRowView()
        rows.append(row)
        listView.stackView.addArrangedSubview(row)
    }
}
