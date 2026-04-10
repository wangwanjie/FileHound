import AppKit
import SnapKit

final class ResultsOutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outlineView = ContextMenuOutlineView()
    private let scrollView = NSScrollView()
    private var items: [SearchResultItem] = []
    private let iconProvider = ResultIconProvider()

    var onSelectionChange: ((SearchResultItem?) -> Void)?
    var onSelectionSetChange: (([SearchResultItem]) -> Void)?
    var contextMenuProvider: (([SearchResultItem]) -> NSMenu?)?
    var onOpenItems: (([SearchResultItem]) -> Void)?
    var onQuickLookRequest: (([SearchResultItem]) -> Void)?

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
        outlineView.doubleAction = #selector(doubleClicked)
        outlineView.allowsMultipleSelection = true
        outlineView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        outlineView.autoresizingMask = [.width, .height]
        outlineView.setAccessibilityElement(true)
        outlineView.setAccessibilityRole(.outline)
        outlineView.setAccessibilityIdentifier("ResultsOutline")
        outlineView.selectionHighlightStyle = .regular
        outlineView.menuProvider = { [weak self] event in
            self?.menu(for: event)
        }
        outlineView.quickLookHandler = { [weak self] in
            self?.quickLookRequested()
        }

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

        let cell = outlineView.makeView(withIdentifier: ResultOutlineCellView.identifier, owner: self) as? ResultOutlineCellView ?? ResultOutlineCellView()
        cell.render(item: result, iconProvider: iconProvider)
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
        representedPath = item.path
        textField?.stringValue = item.displayName
        textField?.identifier = NSUserInterfaceItemIdentifier(item.displayName)
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
