import AppKit
import SnapKit

final class ResultsTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var items: [SearchResultItem] = []

    var onSelectionChange: ((SearchResultItem?) -> Void)?

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "名称"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(selectionDidChange)
        tableView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        tableView.autoresizingMask = [.width, .height]
        tableView.setAccessibilityElement(true)
        tableView.setAccessibilityIdentifier("ResultsTable")

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        view = scrollView
    }

    func update(items: [SearchResultItem]) {
        self.items = items
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ResultsCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.stringValue = URL(fileURLWithPath: items[row].path).lastPathComponent
        textField.identifier = NSUserInterfaceItemIdentifier(textField.stringValue)

        if textField.superview == nil {
            cell.addSubview(textField)
            cell.textField = textField
            textField.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(8)
                make.centerY.equalToSuperview()
            }
        }

        return cell
    }

    @objc
    private func selectionDidChange() {
        let row = tableView.selectedRow
        onSelectionChange?(row >= 0 ? items[row] : nil)
    }
}
