import AppKit
import SnapKit

final class ResultsTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var items: [SearchResultItem] = []

    var onSelectionChange: ((SearchResultItem?) -> Void)?

    override func loadView() {
        addColumn(id: "name", title: "Name", width: 420)
        addColumn(id: "kind", title: "Kind", width: 180)
        addColumn(id: "modified", title: "Modified", width: 180)
        addColumn(id: "size", title: "Size", width: 80)
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

    private func addColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }

    func update(items: [SearchResultItem]) {
        self.items = items
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let identifier = NSUserInterfaceItemIdentifier("ResultsCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.identifier = NSUserInterfaceItemIdentifier(URL(fileURLWithPath: item.path).lastPathComponent)

        switch tableColumn?.identifier.rawValue {
        case "kind":
            textField.stringValue = item.kind
        case "modified":
            textField.stringValue = item.modifiedText
        case "size":
            textField.stringValue = item.sizeText
        default:
            textField.stringValue = URL(fileURLWithPath: item.path).lastPathComponent
        }

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
