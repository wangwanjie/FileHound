import AppKit
import SnapKit

final class ResultsTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = ContextMenuTableView()
    private let scrollView = NSScrollView()
    private var items: [SearchResultItem] = []
    private let iconProvider = ResultIconProvider()
    private var isApplyingSortDescriptor = false

    var onSelectionChange: ((SearchResultItem?) -> Void)?
    var onSelectionSetChange: (([SearchResultItem]) -> Void)?
    var contextMenuProvider: (([SearchResultItem]) -> NSMenu?)?
    var onOpenItems: (([SearchResultItem]) -> Void)?
    var onQuickLookRequest: (([SearchResultItem]) -> Void)?
    var onSortChange: ((SearchResultsViewModel.SortField, SearchResultsViewModel.SortOrder) -> Void)?

    override func loadView() {
        addColumn(id: "name", title: "Name", width: 420, sortField: .name)
        addColumn(id: "kind", title: "Kind", width: 180, sortField: .kind)
        addColumn(id: "modified", title: "Modified", width: 180, sortField: .dateModified)
        addColumn(id: "size", title: "Size", width: 80, sortField: .size)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(selectionDidChange)
        tableView.doubleAction = #selector(doubleClicked)
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        tableView.autoresizingMask = [.width, .height]
        tableView.setAccessibilityElement(true)
        tableView.setAccessibilityIdentifier("ResultsTable")
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.menuProvider = { [weak self] event in
            self?.menu(for: event)
        }
        tableView.quickLookHandler = { [weak self] in
            self?.quickLookRequested()
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        view = scrollView

        applySort(field: .name, order: .ascending)
    }

    private func addColumn(id: String, title: String, width: CGFloat, sortField: SearchResultsViewModel.SortField?) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        if let sortField {
            column.sortDescriptorPrototype = NSSortDescriptor(key: sortDescriptorKey(for: sortField), ascending: true)
        }
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

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard isApplyingSortDescriptor == false,
              let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let field = sortField(for: key) else {
            return
        }

        let order: SearchResultsViewModel.SortOrder = descriptor.ascending ? .ascending : .descending
        onSortChange?(field, order)
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

    func applySort(field: SearchResultsViewModel.SortField, order: SearchResultsViewModel.SortOrder) {
        guard let key = sortDescriptorKeyIfSupported(for: field) else {
            return
        }

        isApplyingSortDescriptor = true
        tableView.sortDescriptors = [NSSortDescriptor(key: key, ascending: order == .ascending)]
        isApplyingSortDescriptor = false
    }

    private func sortField(for key: String) -> SearchResultsViewModel.SortField? {
        switch key {
        case "name":
            return .name
        case "kind":
            return .kind
        case "modified":
            return .dateModified
        case "size":
            return .size
        default:
            return nil
        }
    }

    private func sortDescriptorKey(for field: SearchResultsViewModel.SortField) -> String {
        sortDescriptorKeyIfSupported(for: field) ?? "name"
    }

    private func sortDescriptorKeyIfSupported(for field: SearchResultsViewModel.SortField) -> String? {
        switch field {
        case .name:
            return "name"
        case .kind:
            return "kind"
        case .dateModified:
            return "modified"
        case .size:
            return "size"
        default:
            return nil
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
    private var leadingToIconConstraint: Constraint?
    private var leadingToSuperviewConstraint: Constraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let textField = ResultListTextField()
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
            leadingToIconConstraint = make.leading.equalTo(imageView.snp.trailing).offset(8).constraint
            leadingToSuperviewConstraint = make.leading.equalToSuperview().inset(8).constraint
            make.trailing.equalToSuperview().inset(8)
            make.top.bottom.equalToSuperview().inset(2)
        }
        leadingToSuperviewConstraint?.deactivate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(item: SearchResultItem, columnID: String, iconProvider: ResultIconProvider) {
        representedPath = item.path
        let showsIcon = columnID == "name"
        imageView?.isHidden = showsIcon == false
        if showsIcon {
            leadingToSuperviewConstraint?.deactivate()
            leadingToIconConstraint?.activate()
        } else {
            leadingToIconConstraint?.deactivate()
            leadingToSuperviewConstraint?.activate()
        }
        textField?.identifier = NSUserInterfaceItemIdentifier(item.displayName)
        textField?.textColor = .labelColor

        switch columnID {
        case "kind":
            textField?.stringValue = item.kind
        case "modified":
            textField?.stringValue = item.modifiedText
        case "size":
            textField?.stringValue = item.sizeText
        default:
            textField?.attributedStringValue = SearchResultNameHighlighter.attributedTitle(for: item, baseColor: .labelColor)
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

private final class ResultListTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = ResultListTextFieldCell(textCell: "")
        isBordered = false
        isBezeled = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
        lineBreakMode = .byTruncatingMiddle
        maximumNumberOfLines = 1
        font = .systemFont(ofSize: 13, weight: .regular)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ResultListTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    private func centeredRect(for bounds: NSRect) -> NSRect {
        let baseRect = super.drawingRect(forBounds: bounds)
        let titleSize = cellSize(forBounds: bounds)
        guard baseRect.height > titleSize.height else {
            return baseRect
        }

        return NSRect(
            x: baseRect.origin.x,
            y: baseRect.origin.y + floor((baseRect.height - titleSize.height) / 2),
            width: baseRect.width,
            height: titleSize.height
        )
    }
}

#if DEBUG
extension ResultsTableViewController {
    var debugRowHeight: CGFloat {
        tableView.rowHeight
    }

    func debugNameCellAlignmentOffset(for item: SearchResultItem) -> CGFloat {
        let cell = ResultTableCellView(frame: NSRect(x: 0, y: 0, width: 420, height: tableView.rowHeight))
        cell.render(item: item, columnID: "name", iconProvider: iconProvider)
        cell.layoutSubtreeIfNeeded()
        guard let imageView = cell.imageView, let textField = cell.textField else {
            return .greatestFiniteMagnitude
        }

        let imageRect = imageView.convert(imageView.bounds, to: cell)
        let textRect = textField.convert(textField.cell?.titleRect(forBounds: textField.bounds) ?? textField.bounds, to: cell)
        return abs(imageRect.midY - textRect.midY)
    }
}
#endif
