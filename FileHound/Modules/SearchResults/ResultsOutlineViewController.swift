import AppKit
import SnapKit

final class ResultsOutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outlineView = ContextMenuOutlineView()
    private let scrollView = NSScrollView()
    private var items: [SearchResultItem] = []
    private let iconProvider = ResultIconProvider()
    private var isApplyingSortDescriptor = false
    private var currentSortField: SearchResultsViewModel.SortField = .name
    private var currentSortOrder: SearchResultsViewModel.SortOrder = .ascending
    private var rootNodes: [ResultOutlineNode] = []
    var expandsFoldersOnReload = false

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
        outlineView.rowHeight = 24
        outlineView.intercellSpacing = NSSize(width: 0, height: 1)
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
        let expandedPaths = expandedNodePaths()
        self.items = items
        rootNodes = buildTree(for: items)
        outlineView.reloadData()
        applyExpansionState(expandedPaths)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        childNodes(for: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        childNodes(for: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? ResultOutlineNode else {
            return false
        }

        return node.children.isEmpty == false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? ResultOutlineNode else { return nil }

        let cell = outlineView.makeView(withIdentifier: ResultOutlineCellView.identifier, owner: self) as? ResultOutlineCellView ?? ResultOutlineCellView()
        cell.render(
            item: node.item,
            columnID: tableColumn?.identifier.rawValue ?? "name",
            iconProvider: iconProvider,
            displayName: node.displayTitle,
            highlightName: node.isMatchedResult
        )
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
            guard row >= 0, let node = outlineView.item(atRow: row) as? ResultOutlineNode else {
                return nil
            }
            return node.item
        }
    }

    func applySort(field: SearchResultsViewModel.SortField, order: SearchResultsViewModel.SortOrder) {
        currentSortField = field
        currentSortOrder = order
        let expandedPaths = expandedNodePaths()

        guard let key = sortDescriptorKeyIfSupported(for: field) else {
            rootNodes = sortNodes(rootNodes)
            outlineView.reloadData()
            applyExpansionState(expandedPaths)
            return
        }

        isApplyingSortDescriptor = true
        outlineView.sortDescriptors = [NSSortDescriptor(key: key, ascending: order == .ascending)]
        isApplyingSortDescriptor = false
        rootNodes = sortNodes(rootNodes)
        outlineView.reloadData()
        applyExpansionState(expandedPaths)
    }

    private func childNodes(for item: Any?) -> [ResultOutlineNode] {
        guard let node = item as? ResultOutlineNode else {
            return rootNodes
        }
        return node.children
    }

    private func buildTree(for items: [SearchResultItem]) -> [ResultOutlineNode] {
        guard items.isEmpty == false else {
            return []
        }

        let baseRootPath = commonAncestorPath(for: items.map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path })
        let rootNode = ResultOutlineNode(
            path: baseRootPath,
            item: syntheticItem(for: baseRootPath, isDirectory: true),
            displayTitle: displayTitle(for: baseRootPath),
            isMatchedResult: false
        )

        for item in items {
            insert(item: item, into: rootNode, baseRootPath: baseRootPath)
        }

        return sortNodes([rootNode])
    }

    private func insert(item: SearchResultItem, into rootNode: ResultOutlineNode, baseRootPath: String) {
        let nodePaths = componentPaths(from: baseRootPath, to: item.path)

        guard nodePaths.isEmpty == false else {
            rootNode.update(
                item: item,
                displayTitle: displayTitle(for: item.path, fallback: item.displayName),
                isMatchedResult: true
            )
            return
        }

        var currentNode = rootNode

        for (index, nodePath) in nodePaths.enumerated() {
            let isLeaf = index == nodePaths.count - 1
            if let existingNode = currentNode.children.first(where: { $0.path == nodePath }) {
                if isLeaf {
                    existingNode.update(
                        item: item,
                        displayTitle: displayTitle(for: item.path, fallback: item.displayName),
                        isMatchedResult: true
                    )
                }
                currentNode = existingNode
                continue
            }

            let node = ResultOutlineNode(
                path: nodePath,
                item: isLeaf ? item : syntheticItem(for: nodePath, isDirectory: true),
                displayTitle: displayTitle(for: nodePath, fallback: isLeaf ? item.displayName : nil),
                isMatchedResult: isLeaf
            )
            currentNode.children.append(node)
            currentNode = node
        }
    }

    private func componentPaths(from rootPath: String, to targetPath: String) -> [String] {
        let normalizedRootComponents = pathComponents(for: rootPath)
        let targetComponents = pathComponents(for: targetPath)
        guard targetComponents.count >= normalizedRootComponents.count else {
            return [targetPath]
        }

        var paths: [String] = []
        for index in normalizedRootComponents.count..<targetComponents.count {
            let prefixComponents = Array(targetComponents.prefix(index + 1))
            paths.append(path(from: prefixComponents))
        }
        return paths
    }

    private func commonAncestorPath(for paths: [String]) -> String {
        guard let firstPath = paths.first else {
            return "/"
        }

        var sharedComponents = pathComponents(for: firstPath)

        for path in paths.dropFirst() {
            let candidateComponents = pathComponents(for: path)
            var nextSharedComponents: [String] = []

            for (lhs, rhs) in zip(sharedComponents, candidateComponents) where lhs == rhs {
                nextSharedComponents.append(lhs)
            }

            sharedComponents = nextSharedComponents
            if sharedComponents.count <= 1 {
                break
            }
        }

        return path(from: sharedComponents)
    }

    private func pathComponents(for path: String) -> [String] {
        let components = URL(fileURLWithPath: path).standardized.pathComponents
        return components.isEmpty ? ["/"] : components
    }

    private func path(from components: [String]) -> String {
        guard components.isEmpty == false else {
            return "/"
        }

        guard components != ["/"] else {
            return "/"
        }

        let joinedPath = NSString.path(withComponents: components)
        return joinedPath.isEmpty ? "/" : joinedPath
    }

    private func displayTitle(for path: String, fallback: String? = nil) -> String {
        if path == "/" {
            let displayName = FileManager.default.displayName(atPath: path)
            return displayName == "/" ? "Macintosh HD" : displayName
        }

        let displayName = FileManager.default.displayName(atPath: path)
        if displayName.isEmpty == false, displayName != path {
            return displayName
        }

        return fallback ?? URL(fileURLWithPath: path).lastPathComponent.nilIfEmpty ?? path
    }

    private func syntheticItem(for path: String, isDirectory: Bool) -> SearchResultItem {
        let fileURL = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isVolumeKey]
        let resourceValues = try? fileURL.resourceValues(forKeys: keys)
        let modificationDate = resourceValues?.contentModificationDate
        let isVolume = path == "/" || resourceValues?.isVolume == true || fileURL.deletingLastPathComponent().path == "/Volumes"

        return SearchResultItem(
            path: path,
            matchReason: "",
            previewSnippet: nil,
            kind: isVolume ? L10n.string("results.kind.volume") : (isDirectory ? L10n.string("results.kind.folder") : ""),
            modifiedText: modificationDate.map(Self.modificationDateFormatter.string(from:)) ?? "",
            createdText: "",
            lastOpenedText: "",
            addedText: "",
            sizeText: isDirectory ? "-" : "",
            tagsText: "",
            enclosingFolder: fileURL.deletingLastPathComponent().path,
            modifiedDate: modificationDate
        )
    }

    private func sortNodes(_ nodes: [ResultOutlineNode]) -> [ResultOutlineNode] {
        for node in nodes {
            node.children = sortNodes(node.children)
        }

        return nodes.sorted(by: sortComparator(lhs:rhs:))
    }

    private func sortComparator(lhs: ResultOutlineNode, rhs: ResultOutlineNode) -> Bool {
        let comparison: ComparisonResult

        switch currentSortField {
        case .path:
            comparison = lhs.item.path.localizedStandardCompare(rhs.item.path)
        case .enclosingFolder:
            comparison = lhs.item.enclosingFolder.localizedStandardCompare(rhs.item.enclosingFolder)
        case .kind:
            comparison = lhs.item.kind.localizedStandardCompare(rhs.item.kind)
        case .dateModified:
            comparison = compare(lhs.item.modifiedDate, rhs.item.modifiedDate, fallbackLeft: lhs.displayTitle, fallbackRight: rhs.displayTitle)
        case .dateCreated:
            comparison = compare(lhs.item.createdDate, rhs.item.createdDate, fallbackLeft: lhs.displayTitle, fallbackRight: rhs.displayTitle)
        case .lastOpened:
            comparison = compare(lhs.item.lastOpenedDate, rhs.item.lastOpenedDate, fallbackLeft: lhs.displayTitle, fallbackRight: rhs.displayTitle)
        case .dateAdded:
            comparison = compare(lhs.item.addedDate, rhs.item.addedDate, fallbackLeft: lhs.displayTitle, fallbackRight: rhs.displayTitle)
        case .size:
            comparison = compare(lhs.item.sizeBytes, rhs.item.sizeBytes, fallbackLeft: lhs.displayTitle, fallbackRight: rhs.displayTitle)
        case .tags:
            comparison = lhs.item.tagsText.localizedStandardCompare(rhs.item.tagsText)
        case .name:
            comparison = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
        }

        switch comparison {
        case .orderedAscending:
            return currentSortOrder == .ascending
        case .orderedDescending:
            return currentSortOrder == .descending
        case .orderedSame:
            return lhs.item.path.localizedStandardCompare(rhs.item.path) == .orderedAscending
        }
    }

    private func compare(
        _ lhs: Date?,
        _ rhs: Date?,
        fallbackLeft: String,
        fallbackRight: String
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhsDate?, rhsDate?):
            if lhsDate < rhsDate {
                return .orderedAscending
            }
            if lhsDate > rhsDate {
                return .orderedDescending
            }
            return .orderedSame
        case (nil, nil):
            return fallbackLeft.localizedStandardCompare(fallbackRight)
        case (nil, _?):
            return .orderedAscending
        case (_?, nil):
            return .orderedDescending
        }
    }

    private func compare(
        _ lhs: Int64?,
        _ rhs: Int64?,
        fallbackLeft: String,
        fallbackRight: String
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhsValue?, rhsValue?):
            if lhsValue < rhsValue {
                return .orderedAscending
            }
            if lhsValue > rhsValue {
                return .orderedDescending
            }
            return .orderedSame
        case (nil, nil):
            return fallbackLeft.localizedStandardCompare(fallbackRight)
        case (nil, _?):
            return .orderedAscending
        case (_?, nil):
            return .orderedDescending
        }
    }

    private func expandedNodePaths() -> Set<String> {
        var paths = Set<String>()

        func collect(from nodes: [ResultOutlineNode]) {
            for node in nodes {
                if outlineView.isItemExpanded(node) {
                    paths.insert(node.path)
                }
                collect(from: node.children)
            }
        }

        collect(from: rootNodes)
        return paths
    }

    private func applyExpansionState(_ expandedPaths: Set<String>) {
        guard rootNodes.isEmpty == false else {
            return
        }

        let defaultExpandedPaths = expandableNodePaths(in: rootNodes)
        if expandsFoldersOnReload || expandedPaths.isEmpty {
            outlineView.expandItem(nil, expandChildren: true)
            return
        }

        expand(nodes: rootNodes, using: expandedPaths.union(defaultExpandedPaths))
    }

    private func expand(nodes: [ResultOutlineNode], using expandedPaths: Set<String>) {
        for node in nodes {
            if expandedPaths.contains(node.path) {
                outlineView.expandItem(node)
            }
            expand(nodes: node.children, using: expandedPaths)
        }
    }

    private func expandableNodePaths(in nodes: [ResultOutlineNode]) -> Set<String> {
        var paths = Set<String>()

        func collect(from nodes: [ResultOutlineNode]) {
            for node in nodes where node.children.isEmpty == false {
                paths.insert(node.path)
                collect(from: node.children)
            }
        }

        collect(from: nodes)
        return paths
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

    private static let modificationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
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

private final class ResultOutlineNode {
    let path: String
    var item: SearchResultItem
    var displayTitle: String
    var isMatchedResult: Bool
    var children: [ResultOutlineNode]

    init(
        path: String,
        item: SearchResultItem,
        displayTitle: String,
        isMatchedResult: Bool,
        children: [ResultOutlineNode] = []
    ) {
        self.path = path
        self.item = item
        self.displayTitle = displayTitle
        self.isMatchedResult = isMatchedResult
        self.children = children
    }

    func update(item: SearchResultItem, displayTitle: String, isMatchedResult: Bool) {
        self.item = item
        self.displayTitle = displayTitle
        self.isMatchedResult = isMatchedResult
    }
}

private final class ResultOutlineCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("OutlineCell")

    private var representedPath: String?
    private var leadingToIconConstraint: Constraint?
    private var leadingToSuperviewConstraint: Constraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let textField = ResultOutlineTextField()
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

    func render(
        item: SearchResultItem,
        columnID: String,
        iconProvider: ResultIconProvider,
        displayName: String? = nil,
        highlightName: Bool = true
    ) {
        representedPath = item.path
        textField?.identifier = NSUserInterfaceItemIdentifier(item.displayName)
        let showsIcon = columnID == "name"
        imageView?.isHidden = showsIcon == false
        if showsIcon {
            leadingToSuperviewConstraint?.deactivate()
            leadingToIconConstraint?.activate()
        } else {
            leadingToIconConstraint?.deactivate()
            leadingToSuperviewConstraint?.activate()
        }

        switch columnID {
        case "kind":
            textField?.stringValue = item.kind
        case "modified":
            textField?.stringValue = item.modifiedText
        case "size":
            textField?.stringValue = item.sizeText
        default:
            if highlightName {
                textField?.attributedStringValue = SearchResultNameHighlighter.attributedTitle(for: item, baseColor: .labelColor)
            } else {
                textField?.attributedStringValue = NSAttributedString(
                    string: displayName ?? item.displayName,
                    attributes: [
                        .foregroundColor: NSColor.labelColor,
                        .font: NSFont.systemFont(ofSize: 13, weight: .regular)
                    ]
                )
            }

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

private final class ResultOutlineTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = ResultOutlineTextFieldCell(textCell: "")
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

private final class ResultOutlineTextFieldCell: NSTextFieldCell {
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
extension ResultsOutlineViewController {
    var debugRowHeight: CGFloat {
        outlineView.rowHeight
    }

    func debugNameCellAlignmentOffset(for item: SearchResultItem) -> CGFloat {
        let cell = ResultOutlineCellView(frame: NSRect(x: 0, y: 0, width: 420, height: outlineView.rowHeight))
        cell.render(item: item, columnID: "name", iconProvider: iconProvider)
        cell.layoutSubtreeIfNeeded()
        guard let imageView = cell.imageView, let textField = cell.textField else {
            return .greatestFiniteMagnitude
        }

        let imageRect = imageView.convert(imageView.bounds, to: cell)
        let textRect = textField.convert(textField.cell?.titleRect(forBounds: textField.bounds) ?? textField.bounds, to: cell)
        return abs(imageRect.midY - textRect.midY)
    }

    var debugTreeRows: [(title: String, depth: Int, isMatchedResult: Bool)] {
        flatten(nodes: rootNodes, depth: 0)
    }

    var debugExpandedTitles: Set<String> {
        var titles = Set<String>()

        func collect(from nodes: [ResultOutlineNode]) {
            for node in nodes {
                if outlineView.isItemExpanded(node) {
                    titles.insert(node.displayTitle)
                }
                collect(from: node.children)
            }
        }

        collect(from: rootNodes)
        return titles
    }

    private func flatten(nodes: [ResultOutlineNode], depth: Int) -> [(title: String, depth: Int, isMatchedResult: Bool)] {
        nodes.flatMap { node in
            [(node.displayTitle, depth, node.isMatchedResult)] + flatten(nodes: node.children, depth: depth + 1)
        }
    }
}
#endif

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
