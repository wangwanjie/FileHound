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
    /// 真实匹配结果节点，按结果 ID 索引，用于同步视图模型的选中
    private var matchedNodesByID: [SearchResultItem.ID: ResultOutlineNode] = [:]
    /// 用户（或默认规则）展开的文件夹路径；刷新重建树后据此恢复，保留用户的折叠操作
    private var expandedPaths: Set<String> = []
    /// 已出现过的可展开节点路径；只有新出现的节点才套用默认展开规则
    private var knownExpandableNodePaths: Set<String> = []
    private var isRestoringExpansion = false
    /// 程序化修改选中时不回调，避免把旧选中写回视图模型
    private var isUpdatingSelectionProgrammatically = false
    private(set) var resultsAppearance = ResultsAppearance.current()
    var expandsFoldersOnReload = false

    var onSelectionChange: ((SearchResultItem?) -> Void)?
    var onSelectionSetChange: (([SearchResultItem]) -> Void)?
    var contextMenuProvider: (([SearchResultItem]) -> NSMenu?)?
    var onOpenItems: (([SearchResultItem]) -> Void)?
    var onQuickLookRequest: (([SearchResultItem]) -> Void)?
    var onSortChange: ((SearchResultsViewModel.SortField, SearchResultsViewModel.SortOrder) -> Void)?

    override func loadView() {
        addColumn(id: "name", title: L10n.string("results.column.name"), width: 420, sortField: .name, isOutline: true)
        addColumn(id: "kind", title: L10n.string("results.column.kind"), width: 180, sortField: .kind)
        addColumn(id: "modified", title: L10n.string("results.column.modified"), width: 190, sortField: .dateModified)
        addColumn(id: "size", title: L10n.string("results.column.size"), width: 90, sortField: .size)
        outlineView.delegate = self
        outlineView.dataSource = self
        // 选中变化统一由 outlineViewSelectionDidChange 处理，键盘 ↑↓、⌘A 与鼠标点击都会触发
        outlineView.target = self
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
        outlineView.rowHeight = resultsAppearance.rowHeight
        outlineView.intercellSpacing = NSSize(width: 0, height: 1)
        outlineView.menuProvider = { [weak self] event in
            self?.menu(for: event)
        }
        outlineView.quickLookHandler = { [weak self] in
            self?.quickLookRequested()
        }
        outlineView.appearanceDidChangeHandler = { [weak self] in
            self?.applyAppearance()
        }

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        view = scrollView

        applyAppearance()
        applySort(field: .name, order: .ascending)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resultsAppearanceDidChange(_:)),
            name: AppSettings.resultsAppearanceDidChangeNotification,
            object: nil
        )
    }

    func applyResultsAppearance(_ appearance: ResultsAppearance) {
        resultsAppearance = appearance
        outlineView.rowHeight = appearance.rowHeight
        reloadOutlinePreservingExpansion()
    }

    @objc private func resultsAppearanceDidChange(_ notification: Notification) {
        applyResultsAppearance(.current())
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
        // 搜索进行中结果会持续刷新，按路径恢复选中项，避免选中行因新结果插入而错位
        let selectedPaths = Set(selectedItems().map(\.path))
        isUpdatingSelectionProgrammatically = true
        self.items = items
        rootNodes = buildTree(for: items)
        reloadOutlinePreservingExpansion()
        let rows = IndexSet((0..<outlineView.numberOfRows).filter { row in
            guard let node = outlineView.item(atRow: row) as? ResultOutlineNode else {
                return false
            }
            return selectedPaths.contains(node.item.path)
        })
        if rows != outlineView.selectedRowIndexes {
            outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        }
        isUpdatingSelectionProgrammatically = false
        // 只有选中内容因结果变化真正改变时才通知
        if Set(selectedItems().map(\.path)) != selectedPaths {
            selectionDidChange()
        }
    }

    /// 切换视图模式时把视图模型的选中同步过来（必要时展开上级文件夹），不回调
    func select(ids: Set<SearchResultItem.ID>) {
        let nodes = ids.compactMap { matchedNodesByID[$0] }
        isUpdatingSelectionProgrammatically = true
        for node in nodes {
            expandAncestors(of: node)
        }
        let rows = IndexSet(nodes.map { outlineView.row(forItem: $0) }.filter { $0 >= 0 })
        if rows != outlineView.selectedRowIndexes {
            outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        }
        isUpdatingSelectionProgrammatically = false
        if let first = rows.first {
            outlineView.scrollRowToVisible(first)
        }
    }

    /// 切换语言时刷新列标题；合成节点文案由调用方通过 update(items:) 重建
    func reloadColumnTitles() {
        let titles = [
            "name": L10n.string("results.column.name"),
            "kind": L10n.string("results.column.kind"),
            "modified": L10n.string("results.column.modified"),
            "size": L10n.string("results.column.size")
        ]
        for column in outlineView.tableColumns {
            if let title = titles[column.identifier.rawValue] {
                column.title = title
            }
        }
        outlineView.headerView?.needsDisplay = true
    }

    /// 是否为真实匹配结果；树视图补出的上级文件夹节点返回 false
    func isMatchedResult(_ item: SearchResultItem) -> Bool {
        matchedNodesByID[item.id] != nil
    }

    private func expandAncestors(of node: ResultOutlineNode) {
        var ancestors: [ResultOutlineNode] = []
        var current = node.parent
        while let ancestor = current {
            ancestors.append(ancestor)
            current = ancestor.parent
        }
        for ancestor in ancestors.reversed() where outlineView.isItemExpanded(ancestor) == false {
            outlineView.expandItem(ancestor)
        }
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
            appearance: resultsAppearance,
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

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard isUpdatingSelectionProgrammatically == false else {
            return
        }
        selectionDidChange()
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? ResultOutlineNode else {
            return
        }
        expandedPaths.insert(node.path)
        guard isRestoringExpansion == false else {
            return
        }
        // 用户展开文件夹时恢复其子文件夹之前的展开状态（重建树后子节点是新对象，系统不会记住）
        isRestoringExpansion = true
        restoreExpansion(of: node.children)
        isRestoringExpansion = false
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard isRestoringExpansion == false,
              let node = notification.userInfo?["NSObject"] as? ResultOutlineNode else {
            return
        }
        expandedPaths.remove(node.path)
    }

    /// 拖出结果：只允许真实匹配结果，合成的上级文件夹节点不可拖
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? ResultOutlineNode, node.isMatchedResult else {
            return nil
        }
        return URL(fileURLWithPath: node.item.path) as NSURL
    }

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
            // 选中变化会经 outlineViewSelectionDidChange 通知
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
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

    /// 只记录排序方式并更新表头箭头；视图模型排序变化后会随即通过 update(items:) 按新顺序重建树
    func applySort(field: SearchResultsViewModel.SortField, order: SearchResultsViewModel.SortOrder) {
        currentSortField = field
        currentSortOrder = order
        isApplyingSortDescriptor = true
        if let key = sortDescriptorKeyIfSupported(for: field) {
            outlineView.sortDescriptors = [NSSortDescriptor(key: key, ascending: order == .ascending)]
        } else {
            // 按表头没有的字段（如路径）排序时清除表头上的旧箭头
            outlineView.sortDescriptors = []
        }
        isApplyingSortDescriptor = false
    }

    private func childNodes(for item: Any?) -> [ResultOutlineNode] {
        guard let node = item as? ResultOutlineNode else {
            return rootNodes
        }
        return node.children
    }

    private func buildTree(for items: [SearchResultItem]) -> [ResultOutlineNode] {
        matchedNodesByID.removeAll(keepingCapacity: true)
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
            matchedNodesByID[item.id] = rootNode
            return
        }

        var currentNode = rootNode

        for (index, nodePath) in nodePaths.enumerated() {
            let isLeaf = index == nodePaths.count - 1
            // 子节点按路径字典查找，避免结果很多时逐个线性比较
            if let existingNode = currentNode.child(atPath: nodePath) {
                if isLeaf {
                    existingNode.update(
                        item: item,
                        displayTitle: displayTitle(for: item.path, fallback: item.displayName),
                        isMatchedResult: true
                    )
                    matchedNodesByID[item.id] = existingNode
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
            currentNode.appendChild(node)
            if isLeaf {
                matchedNodesByID[item.id] = node
            }
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

            // 最长公共前缀：遇到第一个不同的组件就停止，不能跳过后继续比较
            for (lhs, rhs) in zip(sharedComponents, candidateComponents) {
                guard lhs == rhs else {
                    break
                }
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
            node.replaceChildren(sortNodes(node.children))
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

    /// 重新加载并按记录恢复展开状态：已出现过的文件夹沿用用户的展开 / 折叠，新出现的套用默认规则
    private func reloadOutlinePreservingExpansion() {
        isRestoringExpansion = true
        outlineView.reloadData()
        restoreExpansion(of: rootNodes)
        isRestoringExpansion = false
    }

    private func restoreExpansion(of nodes: [ResultOutlineNode]) {
        for node in nodes where node.children.isEmpty == false {
            let shouldExpand: Bool
            if knownExpandableNodePaths.contains(node.path) {
                shouldExpand = expandedPaths.contains(node.path)
            } else {
                knownExpandableNodePaths.insert(node.path)
                shouldExpand = shouldExpandByDefault(node)
                if shouldExpand {
                    expandedPaths.insert(node.path)
                }
            }

            // 折叠的文件夹不再递归：其子节点的展开记录保留，用户展开时再恢复
            if shouldExpand {
                outlineView.expandItem(node)
                restoreExpansion(of: node.children)
            }
        }
    }

    /// 默认展开规则：开启「显示结果时展开所有文件夹」时全部展开；否则只展开补出的上级文件夹，
    /// 一直展开到匹配结果所在的层级，匹配到的文件夹本身保持折叠
    private func shouldExpandByDefault(_ node: ResultOutlineNode) -> Bool {
        expandsFoldersOnReload || node.isMatchedResult == false
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

    private func applyAppearance() {
        outlineView.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
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
    var appearanceDidChangeHandler: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(event)
    }

    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        ResultDragOperationPolicy.sourceOperationMask(for: context, modifierFlags: NSEvent.modifierFlags)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChangeHandler?()
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
    private(set) var children: [ResultOutlineNode] = []
    /// 子节点按路径索引，构建大量结果的树时避免线性查找
    private var childrenByPath: [String: ResultOutlineNode] = [:]
    weak var parent: ResultOutlineNode?

    init(
        path: String,
        item: SearchResultItem,
        displayTitle: String,
        isMatchedResult: Bool
    ) {
        self.path = path
        self.item = item
        self.displayTitle = displayTitle
        self.isMatchedResult = isMatchedResult
    }

    func child(atPath path: String) -> ResultOutlineNode? {
        childrenByPath[path]
    }

    func appendChild(_ node: ResultOutlineNode) {
        node.parent = self
        children.append(node)
        childrenByPath[node.path] = node
    }

    /// 排序后替换子节点顺序（节点集合不变）
    func replaceChildren(_ sortedChildren: [ResultOutlineNode]) {
        children = sortedChildren
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
    private var iconSizeConstraint: Constraint?
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
            iconSizeConstraint = make.size.equalTo(16).constraint
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
        appearance: ResultsAppearance,
        displayName: String? = nil,
        highlightName: Bool = true
    ) {
        representedPath = item.path
        textField?.identifier = NSUserInterfaceItemIdentifier(item.displayName)
        textField?.font = appearance.font
        textField?.textColor = appearance.textColor(for: item)
        let showsIcon = columnID == "name"
        imageView?.isHidden = showsIcon == false
        iconSizeConstraint?.update(offset: appearance.listIconSize)
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
                textField?.attributedStringValue = SearchResultNameHighlighter.attributedTitle(
                    for: item,
                    baseColor: appearance.textColor(for: item),
                    font: appearance.font
                )
            } else {
                textField?.attributedStringValue = NSAttributedString(
                    string: displayName ?? item.displayName,
                    attributes: [
                        .foregroundColor: appearance.textColor(for: item),
                        .font: appearance.font
                    ]
                )
            }

            imageView?.image = NSWorkspace.shared.icon(forFile: item.path)
            let path = item.path
            Task { @MainActor [weak self] in
                guard let self else { return }
                let image = await iconProvider.icon(
                    for: URL(fileURLWithPath: path),
                    size: NSSize(width: appearance.listIconSize, height: appearance.listIconSize),
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
        cell.render(item: item, columnID: "name", iconProvider: iconProvider, appearance: resultsAppearance)
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

    var debugTreePaths: [(path: String, depth: Int)] {
        func collect(_ nodes: [ResultOutlineNode], depth: Int) -> [(path: String, depth: Int)] {
            nodes.flatMap { [($0.path, depth)] + collect($0.children, depth: depth + 1) }
        }
        return collect(rootNodes, depth: 0)
    }

    var debugOutlineView: NSOutlineView {
        outlineView
    }

    var debugSortDescriptorKeys: [String] {
        outlineView.sortDescriptors.compactMap(\.key)
    }

    var debugColumnTitles: [String] {
        outlineView.tableColumns.map(\.title)
    }

    /// 按显示标题找到节点所在行（未展开的节点不在行中时返回 nil）
    func debugRow(forTitle title: String) -> Int? {
        (0..<outlineView.numberOfRows).first { row in
            (outlineView.item(atRow: row) as? ResultOutlineNode)?.displayTitle == title
        }
    }

    func debugCollapse(title: String) {
        guard let row = debugRow(forTitle: title), let node = outlineView.item(atRow: row) else {
            return
        }
        outlineView.collapseItem(node)
    }

    func debugExpand(title: String) {
        guard let row = debugRow(forTitle: title), let node = outlineView.item(atRow: row) else {
            return
        }
        outlineView.expandItem(node)
    }

    func debugPasteboardURL(forTitle title: String) -> URL? {
        guard let row = debugRow(forTitle: title), let node = outlineView.item(atRow: row) else {
            return nil
        }
        return (outlineView(outlineView, pasteboardWriterForItem: node) as? NSURL) as URL?
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
