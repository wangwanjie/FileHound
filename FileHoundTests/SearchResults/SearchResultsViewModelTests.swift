import Foundation
import Testing
@testable import FileHound

struct SearchResultsViewModelTests {
    @Test
    func filterTextAndViewModePersistAcrossModeChanges() {
        let viewModel = SearchResultsViewModel()
        viewModel.filterText = "lookin"
        viewModel.sortField = .dateModified
        viewModel.mode = .grid
        viewModel.mode = .tree

        #expect(viewModel.filterText == "lookin")
        #expect(viewModel.sortField == .dateModified)
        #expect(viewModel.mode == .tree)
    }

    @Test
    func projectedItemsHideInvisibleItemsByDefault() {
        let visible = SearchResultItem(path: "/tmp/visible.lookin", matchReason: "名称命中", previewSnippet: nil)
        let hidden = SearchResultItem(path: "/tmp/.hidden.lookin", matchReason: "名称命中", previewSnippet: nil, isInvisible: true)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [visible, hidden]

        #expect(viewModel.projectedItems == [visible])

        viewModel.showInvisibleItems = true
        #expect(viewModel.projectedItems.count == 2)
    }
}
