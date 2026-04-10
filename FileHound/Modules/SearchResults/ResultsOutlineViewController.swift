import AppKit
import SnapKit

final class ResultsOutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outlineView = ContextMenuOutlineView()
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
        addColumn(id: "name", title: "Name", width: 420, sortField: .name, isOutline: true)
        addColumn(id: "kind", title: "Kind", width: 180, sortField: .kind)
        addColumn(id: "modified", title: "Date Modified", width: 190, sortField: .dateModified)
        addColumn(id: "size", title: "Size", width: 90, sortField: .size)
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.target = self
        outlineView.action = #selector(selectionDidChange)
        outlineView.doubleAction = #selector(doubleClicked)
        outlineView.allowsMultipleSelection = true
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        outlineView.autoresizingMask = [.width, .height]
        outlineView.setAccessibilityElement(true)
        outlineView.setAccessibilityRole(.outline)
        outlineView.setAccessibilityIdentifier("ResultsOutline")
        outlineView.selectionHighlightStyle = .regular
        outlineView.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.menuProvider = { [weak self] event in
            self?.menu(for: event)
        }
        outlineView.quickLookHandler = { [weak self] in
            self?.quickLookRequested()
        }

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        view = scrollView

        applySort(field: .name, order: .ascending)
    }

    private func addColumn(
        id: String,
        title: String,
        width: CGFloat,
        sortField: SearchResultsViewModel.SortField?,
        isOutline: Bool = false
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        if let sortField {
            column.sortDescriptorPrototype = NSSortDescriptor(key: sortDescriptorKey(for: sortField), ascending: true)
        }
        outlineView.addTableColumn(column)
        if isOutline {
            outlineView.outlineTableColumn = column
        }
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

        let cell = outlineView.makeView(withIdentifier: ResultOutlineCellView.identifier, owner: self) as? ResultOutlineCellView ?? ResultOutlineCellView()
        cell.render(item: result, columnID: tableColumn?.identifier.rawValue ?? "name", iconProvider: iconProvider)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard isApplyingSortDescriptor == false,
              let descriptor = outlineView.sortDescriptors.first,
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
        let point = outlineView.convert(event.locationInWindow, from: nil)
        let row = outlineView.row(at: point)
        if row >= 0, outlineView.selectedRowIndexes.contains(row) == false {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            selectionDidChange()
        }

        let selected = selectedItems()
        return selected.isEmpty ? nil : contextMenuProvider?(selected)
    }

    private func selectedItems() -> [SearchResultItem] {
        outlineView.selectedRowIndexes.compactMap { row in
            guard row >= 0, let item = outlineView.item(atRow: row) as? SearchResultItem else {
                return nil
            }
            return item
        }
    }

    func applySort(field: SearchResultsViewModel.SortField, order: SearchResultsViewModel.SortOrder) {
        guard let key = sortDescriptorKeyIfSupported(for: field) else {
            return
        }

        isApplyingSortDescriptor = true
        outlineView.sortDescriptors = [NSSortDescriptor(key: key, ascending: order == .ascending)]
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

private final class ContextMenuOutlineView: NSOutlineView {
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

private final class ResultOutlineCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("OutlineCell")

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

    func render(item: SearchResultItem, iconProvider: ResultIconProvider) {
        render(item: item, columnID: "name", iconProvider: iconProvider)
    }

    func render(item: SearchResultItem, columnID: String, iconProvider: ResultIconProvider) {
        representedPath = item.path
        textField?.identifier = NSUserInterfaceItemIdentifier(item.displayName)
        imageView?.isHidden = columnID != "name"

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
