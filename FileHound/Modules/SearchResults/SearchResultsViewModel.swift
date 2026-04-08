import Foundation

final class SearchResultsViewModel {
    enum Mode {
        case list
        case tree
    }

    var mode: Mode = .list {
        didSet { onModeChange?(mode) }
    }

    var items: [SearchResultItem] = [] {
        didSet { onItemsChange?(items) }
    }

    var selectedItem: SearchResultItem? {
        didSet { onSelectionChange?(selectedItem) }
    }

    var onModeChange: ((Mode) -> Void)?
    var onItemsChange: (([SearchResultItem]) -> Void)?
    var onSelectionChange: ((SearchResultItem?) -> Void)?
}
