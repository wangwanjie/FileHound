import AppKit

final class ResultsOutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private var items: [SearchResultItem] = []

    var onSelectionChange: ((SearchResultItem?) -> Void)?

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("outline"))
        column.title = "名称"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.target = self
        outlineView.action = #selector(selectionDidChange)
        outlineView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        outlineView.autoresizingMask = [.width, .height]
        outlineView.setAccessibilityElement(true)
        outlineView.setAccessibilityRole(.outline)
        outlineView.setAccessibilityIdentifier("ResultsOutline")

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        view = scrollView
    }

    func update(items: [SearchResultItem]) {
        self.items = items
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        item == nil ? items.count : 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        items[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let result = item as? SearchResultItem else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("OutlineCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        let title = URL(fileURLWithPath: result.path).lastPathComponent
        textField.stringValue = title
        textField.identifier = NSUserInterfaceItemIdentifier(title)
        textField.translatesAutoresizingMaskIntoConstraints = false

        if textField.superview == nil {
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        return cell
    }

    @objc
    private func selectionDidChange() {
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? SearchResultItem else {
            onSelectionChange?(nil)
            return
        }
        onSelectionChange?(item)
    }
}
