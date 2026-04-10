import AppKit
import SnapKit

final class ResultsTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = ContextMenuTableView()
    private let scrollView = NSScrollView()
    private var items: [SearchResultItem] = []
    private let iconProvider = ResultIconProvider()

    var onSelectionChange: ((SearchResultItem?) -> Void)?
    var onSelectionSetChange: (([SearchResultItem]) -> Void)?
    var contextMenuProvider: (([SearchResultItem]) -> NSMenu?)?
    var onOpenItems: (([SearchResultItem]) -> Void)?
    var onQuickLookRequest: (([SearchResultItem]) -> Void)?

    override func loadView() {
        addColumn(id: "name", title: "Name", width: 420)
        addColumn(id: "kind", title: "Kind", width: 180)
        addColumn(id: "modified", title: "Modified", width: 180)
        addColumn(id: "size", title: "Size", width: 80)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(selectionDidChange)
        tableView.doubleAction = #selector(doubleClicked)
        tableView.allowsMultipleSelection = true
        tableView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        tableView.autoresizingMask = [.width, .height]
        tableView.setAccessibilityElement(true)
        tableView.setAccessibilityIdentifier("ResultsTable")
        tableView.selectionHighlightStyle = .regular
        tableView.menuProvider = { [weak self] event in
            self?.menu(for: event)
        }
        tableView.quickLookHandler = { [weak self] in
            self?.quickLookRequested()
        }

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
        let cell = tableView.makeView(withIdentifier: ResultTableCellView.identifier, owner: self) as? ResultTableCellView ?? ResultTableCellView()
        cell.render(item: item, columnID: tableColumn?.identifier.rawValue ?? "name", iconProvider: iconProvider)
        return cell
    }

    @objc
    private func selectionDidChange() {
        let selected = selectedItems()
        onSelectionSetChange?(selected)
        onSelectionChange?(selected.first)
    }

    @objc
    private func doubleClicked() {
        let selected = selectedItems()
        guard selected.isEmpty == false else {
            return
        }
        onOpenItems?(selected)
    }

    private func quickLookRequested() {
        let selected = selectedItems()
        guard selected.isEmpty == false else {
            return
        }
        onQuickLookRequest?(selected)
    }

    private func menu(for event: NSEvent) -> NSMenu? {
        let point = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: point)
        if row >= 0, tableView.selectedRowIndexes.contains(row) == false {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            selectionDidChange()
        }

        let selected = selectedItems()
        return selected.isEmpty ? nil : contextMenuProvider?(selected)
    }

    private func selectedItems() -> [SearchResultItem] {
        tableView.selectedRowIndexes.compactMap { row in
            items.indices.contains(row) ? items[row] : nil
        }
    }
}

private final class ContextMenuTableView: NSTableView {
    var menuProvider: ((NSEvent) -> NSMenu?)?
    var quickLookHandler: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            quickLookHandler?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class ResultTableCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultTableCell")

    private var representedPath: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingMiddle
        self.imageView = imageView
        self.textField = textField
        addSubview(imageView)
        addSubview(textField)

        imageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(16)
        }
        textField.snp.makeConstraints { make in
            make.leading.equalTo(imageView.snp.trailing).offset(8)
            make.trailing.equalToSuperview().inset(8)
            make.centerY.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(item: SearchResultItem, columnID: String, iconProvider: ResultIconProvider) {
        representedPath = item.path
        imageView?.isHidden = columnID != "name"
        textField?.identifier = NSUserInterfaceItemIdentifier(item.displayName)

        switch columnID {
        case "kind":
            textField?.stringValue = item.kind
        case "modified":
            textField?.stringValue = item.modifiedText
        case "size":
            textField?.stringValue = item.sizeText
        default:
            textField?.stringValue = item.displayName
            imageView?.image = NSWorkspace.shared.icon(forFile: item.path)
            let path = item.path
            Task { @MainActor [weak self] in
                guard let self else { return }
                let image = await iconProvider.icon(
                    for: URL(fileURLWithPath: path),
                    size: NSSize(width: 16, height: 16),
                    preferThumbnail: false
                )
                guard self.representedPath == path else { return }
                self.imageView?.image = image
            }
        }
    }
}
