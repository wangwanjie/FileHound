import Foundation

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
    var sortField: SortField = .name {
        didSet { notifyProjectionChanged() }
    }

    var mode: Mode = .grid {
        didSet { onModeChange?(mode) }
    }

    var items: [SearchResultItem] = [] {
        didSet { notifyProjectionChanged() }
    }

    var selectedIDs: Set<SearchResultItem.ID> = []

    var selectedItems: [SearchResultItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedItem: SearchResultItem? {
        didSet { onSelectionChange?(selectedItem) }
    }

    var onModeChange: ((Mode) -> Void)?
    var onItemsChange: (([SearchResultItem]) -> Void)?
    var onSelectionChange: ((SearchResultItem?) -> Void)?
    var onFilterChange: ((String) -> Void)?

    var projectedItems: [SearchResultItem] {
        items
            .filter { showInvisibleItems || $0.isInvisible == false }
            .filter { showPackageContents || $0.isPackage == false }
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
    }

    func replaceItems(_ updatedItems: [SearchResultItem]) {
        let itemsByID = Dictionary(uniqueKeysWithValues: updatedItems.map { ($0.id, $0) })
        items = items.map { itemsByID[$0.id] ?? $0 }
    }

    private func sortComparator(lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        switch sortField {
        case .path:
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        case .enclosingFolder:
            return lhs.enclosingFolder.localizedStandardCompare(rhs.enclosingFolder) == .orderedAscending
        case .kind:
            return lhs.kind.localizedStandardCompare(rhs.kind) == .orderedAscending
        default:
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }
}
