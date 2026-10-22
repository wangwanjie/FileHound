import Foundation
import UniformTypeIdentifiers

/// 被移到废纸篓的结果项，记录原始项与其在废纸篓中的位置，用于「放回原处」后恢复显示
struct TrashedResultEntry: Equatable {
    let item: SearchResultItem
    let trashedPath: String
}

final class SearchResultsViewModel {
    enum Mode: Equatable {
        case grid
        case table
        case tree
    }

    enum SortField: Equatable {
        case name
        case dateModified
        case dateCreated
        case lastOpened
        case dateAdded
        case kind
        case size
        case tags
        case enclosingFolder
        case path
    }

    enum SortOrder: Equatable {
        case ascending
        case descending
    }

    /// 结果页对应搜索的进度：提前显示结果时，结果页会在搜索仍在进行中打开
    enum SearchStatus: Equatable {
        case searching
        case finished
        case stopped
    }

    var title: String = ""
    var filterText: String = "" {
        didSet { notifyProjectionChanged() }
    }
    var showInvisibleItems = false {
        didSet { notifyProjectionChanged() }
    }
    var showPackageContents = false {
        didSet { notifyProjectionChanged() }
    }
    var showTrashedItems = false {
        didSet { notifyProjectionChanged() }
    }
    var previewSize: Double = 72 {
        didSet { onPreviewSizeChange?(previewSize) }
    }
    var sortField: SortField = .name {
        didSet {
            onSortChange?(sortField, sortOrder)
            notifyProjectionChanged()
        }
    }
    var sortOrder: SortOrder = .ascending {
        didSet {
            onSortChange?(sortField, sortOrder)
            notifyProjectionChanged()
        }
    }

    var mode: Mode = .grid {
        didSet { onModeChange?(mode) }
    }

    var items: [SearchResultItem] = [] {
        didSet {
            itemIDs = Set(items.map(\.id))
            remapSelection(from: oldValue)
            notifyProjectionChanged()
        }
    }

    var selectedIDs: Set<SearchResultItem.ID> = []

    var searchStatus: SearchStatus = .finished {
        didSet {
            guard searchStatus != oldValue else { return }
            onSearchStatusChange?(searchStatus)
        }
    }

    private(set) var trashedEntries: [TrashedResultEntry] = []

    /// 当前结果项 ID 集合，用于快速判断某项是否为真实匹配结果（树视图的合成文件夹节点不在其中）
    private var itemIDs: Set<SearchResultItem.ID> = []
    /// 投影结果缓存：过滤 / 排序条件或结果变化时失效，避免每次读取都对全部结果重新排序
    private var cachedProjectedItems: [SearchResultItem]?
    /// 批量更新嵌套深度，大于 0 时暂不发出投影变化通知
    private var batchUpdateDepth = 0
    private var hasPendingProjectionChange = false

    /// 用户在本次搜索中做过的修改，流式进度整体替换结果时需要重新应用，避免被移除 / 改名的项又被加回来
    /// 被用户移除的精确路径（「从结果中移除」，不影响后代）
    private var userRemovedPaths: Set<String> = []
    /// 被删除或移到废纸篓的路径，其后代结果一并视为已移除
    private var userRemovedSubtreePaths: Set<String> = []
    /// 用户改名记录：旧路径 → 新路径（文件夹改名同时作用于后代）
    private var userRenamedPaths: [String: String] = [:]
    /// 用户操作后刷新过的结果（改名、隐藏、解锁、标签），按当前路径索引
    private var userUpdatedItems: [String: SearchResultItem] = [:]

    var selectedItems: [SearchResultItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedItem: SearchResultItem? {
        didSet { onSelectionChange?(selectedItem) }
    }

    var onModeChange: ((Mode) -> Void)?
    var onItemsChange: (([SearchResultItem]) -> Void)?
    var onSearchStatusChange: ((SearchStatus) -> Void)?
    var onSelectionChange: ((SearchResultItem?) -> Void)?
    var onFilterChange: ((String) -> Void)?
    var onSortChange: ((SortField, SortOrder) -> Void)?
    var onPreviewSizeChange: ((Double) -> Void)?

    var projectedItems: [SearchResultItem] {
        if let cachedProjectedItems {
            return cachedProjectedItems
        }

        let projected = items
            .filter { showInvisibleItems || $0.isInvisible == false }
            .filter { showPackageContents || $0.isInsidePackageContents == false }
            .filter { showTrashedItems || $0.isTrashed == false }
            .filter { filterText.isEmpty || $0.path.localizedCaseInsensitiveContains(filterText) }
            .sorted(by: sortComparator)
        cachedProjectedItems = projected
        return projected
    }

    /// 是否为当前结果中的真实匹配项；树视图中补出的上级文件夹节点不是
    func containsItem(id: SearchResultItem.ID) -> Bool {
        itemIDs.contains(id)
    }

    /// 合并多次属性修改，只在结束时发出一次投影变化通知
    func performBatchUpdates(_ updates: () -> Void) {
        batchUpdateDepth += 1
        updates()
        batchUpdateDepth -= 1
        if batchUpdateDepth == 0, hasPendingProjectionChange {
            hasPendingProjectionChange = false
            notifyProjectionChanged()
        }
    }

    private func notifyProjectionChanged() {
        cachedProjectedItems = nil
        guard batchUpdateDepth == 0 else {
            hasPendingProjectionChange = true
            return
        }
        onFilterChange?(filterText)
        onItemsChange?(projectedItems)
    }

    /// 结果整体替换（如流式进度）时 ID 可能变化，按路径把选中状态迁移到新结果上
    private func remapSelection(from oldItems: [SearchResultItem]) {
        guard selectedIDs.isEmpty == false else {
            return
        }

        let selectedPaths = Set(oldItems.lazy.filter { self.selectedIDs.contains($0.id) }.map(\.path))
        selectedIDs = Set(items.lazy.filter { selectedPaths.contains($0.path) }.map(\.id))
        if let selectedItem, itemIDs.contains(selectedItem.id) == false {
            self.selectedItem = items.first { $0.path == selectedItem.path } ?? selectedItems.first
        }
    }

    /// 开始新搜索：清空用户在上一次搜索结果上做的移除 / 改名记录以及废纸篓跟踪
    func beginNewSearch(with newItems: [SearchResultItem]) {
        userRemovedPaths.removeAll()
        userRemovedSubtreePaths.removeAll()
        userRenamedPaths.removeAll()
        userUpdatedItems.removeAll()
        trashedEntries.removeAll()
        items = newItems
    }

    /// 合并同一次搜索的流式进度：应用用户的移除 / 改名 / 刷新记录后再替换结果
    func mergeSearchProgress(_ newItems: [SearchResultItem]) {
        var seenPaths = Set<String>()
        var merged: [SearchResultItem] = []
        merged.reserveCapacity(newItems.count)
        for item in newItems {
            let currentPath = mappedPath(for: item.path)
            guard isRemovedByUser(path: currentPath) == false,
                  seenPaths.insert(currentPath).inserted else {
                continue
            }

            if let updated = userUpdatedItems[currentPath] {
                merged.append(updated)
            } else if currentPath != item.path {
                merged.append(item.withUpdatedPath(currentPath))
            } else {
                merged.append(item)
            }
        }
        items = merged
    }

    /// 按改名记录把搜索得到的旧路径换成当前路径；文件夹改名作用于其后代，支持连续改名
    private func mappedPath(for path: String) -> String {
        guard userRenamedPaths.isEmpty == false else {
            return path
        }

        var current = path
        // 连续改名（A→B→C）最多迭代记录条数次，防止异常记录导致死循环
        for _ in 0...userRenamedPaths.count {
            guard let (oldPrefix, newPrefix) = renamedAncestor(of: current) else {
                break
            }
            current = newPrefix + current.dropFirst(oldPrefix.count)
        }
        return current
    }

    /// 自身或最近的已改名祖先路径
    private func renamedAncestor(of path: String) -> (String, String)? {
        var candidate = path
        while candidate.isEmpty == false, candidate != "/" {
            if let renamed = userRenamedPaths[candidate] {
                return (candidate, renamed)
            }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return nil
    }

    private func isRemovedByUser(path: String) -> Bool {
        if userRemovedPaths.contains(path) {
            return true
        }
        guard userRemovedSubtreePaths.isEmpty == false else {
            return false
        }

        var candidate = path
        while candidate.isEmpty == false, candidate != "/" {
            if userRemovedSubtreePaths.contains(candidate) {
                return true
            }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return false
    }

    /// 「从结果中移除」：只移除选中的项本身，并记录下来避免后续进度把它们加回来
    func removeItems(ids: Set<SearchResultItem.ID>) {
        let removedPaths = items.filter { ids.contains($0.id) }.map(\.path)
        userRemovedPaths.formUnion(removedPaths)
        removeFromItems { ids.contains($0.id) }
    }

    /// 文件被删除或移到废纸篓：移除这些项及以其为前缀的后代结果
    func removeItemsAndDescendants(paths: Set<String>) {
        guard paths.isEmpty == false else {
            return
        }

        userRemovedSubtreePaths.formUnion(paths)
        removeFromItems { item in
            paths.contains(item.path) || Self.hasAncestor(in: paths, path: item.path)
        }
    }

    private func removeFromItems(where shouldRemove: (SearchResultItem) -> Bool) {
        let removedIDs = Set(items.filter(shouldRemove).map(\.id))
        guard removedIDs.isEmpty == false else {
            return
        }

        selectedIDs.subtract(removedIDs)
        items.removeAll { removedIDs.contains($0.id) }
        selectedItem = selectedItems.first
    }

    private static func hasAncestor(in paths: Set<String>, path: String) -> Bool {
        var candidate = (path as NSString).deletingLastPathComponent
        while candidate.isEmpty == false, candidate != "/" {
            if paths.contains(candidate) {
                return true
            }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return false
    }

    func markItemsTrashed(_ entries: [TrashedResultEntry]) {
        guard entries.isEmpty == false else {
            return
        }

        let ids = Set(entries.map(\.item.id))
        trashedEntries.removeAll { ids.contains($0.item.id) }
        trashedEntries.append(contentsOf: entries)
        removeItemsAndDescendants(paths: Set(entries.map(\.item.path)))
    }

    /// 检查已移到废纸篓的项：回到原位置的重新加入结果并返回；原位置与废纸篓中都已不存在的不再跟踪
    @discardableResult
    func restoreItemsPutBackFromTrash(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [SearchResultItem] {
        guard trashedEntries.isEmpty == false else {
            return []
        }

        let existingPaths = Set(items.map(\.path))
        var restored: [SearchResultItem] = []
        var remaining: [TrashedResultEntry] = []
        for entry in trashedEntries {
            if fileExists(entry.item.path) {
                if existingPaths.contains(entry.item.path) == false {
                    restored.append(entry.item)
                }
            } else if fileExists(entry.trashedPath) {
                remaining.append(entry)
            }
        }

        trashedEntries = remaining
        if restored.isEmpty == false {
            // 放回原处后不再视为用户移除，后续进度中的该项可以正常显示
            userRemovedSubtreePaths.subtract(restored.map(\.path))
            items.append(contentsOf: restored)
        }
        return restored
    }

    func discardTrashedEntries() {
        trashedEntries.removeAll()
    }

    /// 用户操作（隐藏、解锁、标签等）后用刷新过的结果替换原项，并记录下来供后续进度合并时使用
    func replaceItems(_ updatedItems: [SearchResultItem]) {
        guard updatedItems.isEmpty == false else {
            return
        }

        let itemsByID = Dictionary(updatedItems.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for item in updatedItems {
            userUpdatedItems[item.path] = item
        }
        items = items.map { itemsByID[$0.id] ?? $0 }
        selectedItem = selectedItems.first
    }

    /// 改名后更新结果：替换该项，并把以旧路径为前缀的后代结果路径批量换成新路径
    func applyRename(from oldPath: String, to renamedItem: SearchResultItem) {
        let newPath = renamedItem.path
        guard oldPath != newPath else {
            replaceItems([renamedItem])
            return
        }

        // 已有记录若指向旧路径，直接改指新路径；改回原名产生的 X→X 记录删除，避免出现循环
        for (source, target) in userRenamedPaths where target == oldPath {
            userRenamedPaths[source] = newPath
        }
        userRenamedPaths[oldPath] = newPath
        userRenamedPaths = userRenamedPaths.filter { $0.key != $0.value }
        // 之前针对旧路径及其后代记录的刷新结果同样迁移到新路径
        let oldPrefix = oldPath + "/"
        var migratedUpdates: [String: SearchResultItem] = [:]
        for (path, item) in userUpdatedItems {
            if path == oldPath {
                continue
            } else if path.hasPrefix(oldPrefix) {
                let migratedPath = newPath + "/" + path.dropFirst(oldPrefix.count)
                migratedUpdates[migratedPath] = item.withUpdatedPath(migratedPath)
            } else {
                migratedUpdates[path] = item
            }
        }
        migratedUpdates[newPath] = renamedItem
        userUpdatedItems = migratedUpdates

        items = items.map { item in
            if item.id == renamedItem.id || item.path == oldPath {
                return renamedItem
            }
            if item.path.hasPrefix(oldPrefix) {
                return item.withUpdatedPath(newPath + "/" + item.path.dropFirst(oldPrefix.count))
            }
            return item
        }
        selectedItem = selectedItems.first
    }

    var presentationState: ResultPresentationState {
        ResultPresentationState(
            mode: mode.resultViewMode,
            sortField: sortField.resultSortField,
            sortOrder: sortOrder.resultSortOrder,
            filterText: filterText,
            showInvisibleItems: showInvisibleItems,
            showPackageContents: showPackageContents,
            showTrashedItems: showTrashedItems,
            previewSize: previewSize
        )
    }

    func apply(presentationState: ResultPresentationState) {
        // 合并为一次投影刷新，避免逐个属性触发重排与视图刷新
        performBatchUpdates {
            mode = Mode(presentationState.mode)
            filterText = presentationState.filterText
            showInvisibleItems = presentationState.showInvisibleItems
            showPackageContents = presentationState.showPackageContents
            showTrashedItems = presentationState.showTrashedItems
            previewSize = presentationState.previewSize
            sortField = SortField(presentationState.sortField)
            sortOrder = SortOrder(presentationState.sortOrder)
        }
    }

    private func sortComparator(lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        let comparison: ComparisonResult

        switch sortField {
        case .path:
            comparison = lhs.path.localizedStandardCompare(rhs.path)
        case .enclosingFolder:
            comparison = lhs.enclosingFolder.localizedStandardCompare(rhs.enclosingFolder)
        case .kind:
            comparison = lhs.kind.localizedStandardCompare(rhs.kind)
        case .dateModified:
            comparison = compare(lhs.modifiedDate, rhs.modifiedDate, fallbackLeft: lhs.modifiedText, fallbackRight: rhs.modifiedText)
        case .dateCreated:
            comparison = compare(lhs.createdDate, rhs.createdDate, fallbackLeft: lhs.createdText, fallbackRight: rhs.createdText)
        case .lastOpened:
            comparison = compare(lhs.lastOpenedDate, rhs.lastOpenedDate, fallbackLeft: lhs.lastOpenedText, fallbackRight: rhs.lastOpenedText)
        case .dateAdded:
            comparison = compare(lhs.addedDate, rhs.addedDate, fallbackLeft: lhs.addedText, fallbackRight: rhs.addedText)
        case .size:
            comparison = compare(lhs.sizeBytes, rhs.sizeBytes, fallbackLeft: lhs.sizeText, fallbackRight: rhs.sizeText)
        case .tags:
            comparison = lhs.tagsText.localizedStandardCompare(rhs.tagsText)
        default:
            comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
        }

        switch comparison {
        case .orderedAscending:
            return sortOrder == .ascending
        case .orderedDescending:
            return sortOrder == .descending
        case .orderedSame:
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
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
}

private extension SearchResultsViewModel.Mode {
    init(_ mode: ResultViewMode) {
        switch mode {
        case .grid:
            self = .grid
        case .table:
            self = .table
        case .tree:
            self = .tree
        }
    }

    var resultViewMode: ResultViewMode {
        switch self {
        case .grid:
            return .grid
        case .table:
            return .table
        case .tree:
            return .tree
        }
    }
}

private extension SearchResultsViewModel.SortField {
    init(_ field: ResultSortField) {
        switch field {
        case .name:
            self = .name
        case .dateModified:
            self = .dateModified
        case .dateCreated:
            self = .dateCreated
        case .lastOpened:
            self = .lastOpened
        case .dateAdded:
            self = .dateAdded
        case .kind:
            self = .kind
        case .size:
            self = .size
        case .tags:
            self = .tags
        case .enclosingFolder:
            self = .enclosingFolder
        case .path:
            self = .path
        }
    }

    var resultSortField: ResultSortField {
        switch self {
        case .name:
            return .name
        case .dateModified:
            return .dateModified
        case .dateCreated:
            return .dateCreated
        case .lastOpened:
            return .lastOpened
        case .dateAdded:
            return .dateAdded
        case .kind:
            return .kind
        case .size:
            return .size
        case .tags:
            return .tags
        case .enclosingFolder:
            return .enclosingFolder
        case .path:
            return .path
        }
    }
}

private extension SearchResultsViewModel.SortOrder {
    init(_ order: ResultSortOrder) {
        switch order {
        case .ascending:
            self = .ascending
        case .descending:
            self = .descending
        }
    }

    var resultSortOrder: ResultSortOrder {
        switch self {
        case .ascending:
            return .ascending
        case .descending:
            return .descending
        }
    }
}

/// 导出结果的文件格式
enum ResultExportFormat: CaseIterable, Equatable {
    case csv
    case plainText

    var fileExtension: String {
        switch self {
        case .csv:
            return "csv"
        case .plainText:
            return "txt"
        }
    }

    var contentType: UTType {
        switch self {
        case .csv:
            return .commaSeparatedText
        case .plainText:
            return .plainText
        }
    }

    var localizedTitle: String {
        switch self {
        case .csv:
            return L10n.string("results.export.format.csv")
        case .plainText:
            return L10n.string("results.export.format.text")
        }
    }
}

/// 导出结果的格式化（纯函数，便于单元测试）
enum ResultExportFormatter {
    /// UTF-8 BOM：Excel 依赖它识别 UTF-8，否则中文会乱码
    static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    static func data(for items: [SearchResultItem], format: ResultExportFormat, timeZone: TimeZone = .current) -> Data {
        switch format {
        case .csv:
            return Data(utf8BOM) + Data(csvString(for: items, timeZone: timeZone).utf8)
        case .plainText:
            return Data(plainText(for: items).utf8)
        }
    }

    /// CSV（RFC 4180）：列为名称、路径、大小（字节）、修改日期（ISO 8601）、种类；行尾用 CRLF
    static func csvString(for items: [SearchResultItem], timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone

        let header = [
            L10n.string("results.export.column.name"),
            L10n.string("results.export.column.path"),
            L10n.string("results.export.column.size_bytes"),
            L10n.string("results.export.column.modified"),
            L10n.string("results.export.column.kind")
        ]
        let rows = items.map { item in
            [
                item.displayName,
                item.path,
                item.sizeBytes.map(String.init) ?? "",
                item.modifiedDate.map(formatter.string(from:)) ?? "",
                item.kind
            ]
        }
        return ([header] + rows)
            .map { $0.map(csvEscaped).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    /// 纯文本：每行一个路径
    static func plainText(for items: [SearchResultItem]) -> String {
        items.map(\.path).joined(separator: "\n") + (items.isEmpty ? "" : "\n")
    }

    /// 含逗号、双引号、换行的字段整体加双引号，内部双引号写成两个
    static func csvEscaped(_ field: String) -> String {
        let needsQuoting = field.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }
        guard needsQuoting else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// 默认文件名：用搜索标题，去掉文件名中不允许的 "/" 与 ":"
    static func suggestedFileName(title: String, fallback: String, format: ResultExportFormat) -> String {
        let sanitized = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitized.isEmpty ? fallback : sanitized
        return baseName + "." + format.fileExtension
    }
}
