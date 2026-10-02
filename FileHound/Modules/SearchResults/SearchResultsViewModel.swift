import Foundation

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
        didSet { notifyProjectionChanged() }
    }

    var selectedIDs: Set<SearchResultItem.ID> = []

    var searchStatus: SearchStatus = .finished {
        didSet {
            guard searchStatus != oldValue else { return }
            onSearchStatusChange?(searchStatus)
        }
    }

    private(set) var trashedEntries: [TrashedResultEntry] = []

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
        items
            .filter { showInvisibleItems || $0.isInvisible == false }
            .filter { showPackageContents || $0.isInsidePackageContents == false }
            .filter { showTrashedItems || $0.isTrashed == false }
            .filter { filterText.isEmpty || $0.path.localizedCaseInsensitiveContains(filterText) }
            .sorted(by: sortComparator)
    }

    private func notifyProjectionChanged() {
        onFilterChange?(filterText)
        onItemsChange?(projectedItems)
    }

    func removeItems(ids: Set<SearchResultItem.ID>) {
        items.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        selectedItem = selectedItems.first
    }

    func markItemsTrashed(_ entries: [TrashedResultEntry]) {
        guard entries.isEmpty == false else {
            return
        }

        let ids = Set(entries.map(\.item.id))
        trashedEntries.removeAll { ids.contains($0.item.id) }
        trashedEntries.append(contentsOf: entries)
        removeItems(ids: ids)
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
            items.append(contentsOf: restored)
        }
        return restored
    }

    func discardTrashedEntries() {
        trashedEntries.removeAll()
    }

    func replaceItems(_ updatedItems: [SearchResultItem]) {
        let itemsByID = Dictionary(uniqueKeysWithValues: updatedItems.map { ($0.id, $0) })
        items = items.map { itemsByID[$0.id] ?? $0 }
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
        mode = Mode(presentationState.mode)
        filterText = presentationState.filterText
        showInvisibleItems = presentationState.showInvisibleItems
        showPackageContents = presentationState.showPackageContents
        showTrashedItems = presentationState.showTrashedItems
        previewSize = presentationState.previewSize
        sortField = SortField(presentationState.sortField)
        sortOrder = SortOrder(presentationState.sortOrder)
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
