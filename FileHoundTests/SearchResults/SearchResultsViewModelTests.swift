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

    @Test
    func togglesPackageFilterWithoutDroppingVisibleFiles() {
        let package = SearchResultItem(path: "/tmp/Demo.app", matchReason: "名称命中", previewSnippet: nil, isPackage: true)
        let file = SearchResultItem(path: "/tmp/Demo.lookin", matchReason: "名称命中", previewSnippet: nil)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [package, file]

        #expect(viewModel.projectedItems.count == 1)
        viewModel.showPackageContents = true
        #expect(viewModel.projectedItems.count == 2)
    }

    @Test
    func sortByPathUsesFullPathInsteadOfDisplayName() {
        let a = SearchResultItem(path: "/z/report.lookin", matchReason: "名称命中", previewSnippet: nil)
        let b = SearchResultItem(path: "/a/report.lookin", matchReason: "名称命中", previewSnippet: nil)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [a, b]
        viewModel.sortField = .path

        #expect(viewModel.projectedItems.map(\.path) == ["/a/report.lookin", "/z/report.lookin"])
    }

    @Test
    func removesUpdatedAndSelectedItemsWithoutRebuildingWindow() {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "名称命中", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "名称命中", previewSnippet: nil)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [first, second]
        viewModel.selectedIDs = [first.id, second.id]

        viewModel.removeItems(ids: [first.id])
        #expect(viewModel.items.map(\.path) == ["/tmp/b.txt"])
        #expect(viewModel.selectedIDs == [second.id])

        let renamed = second.withUpdatedPath("/tmp/renamed.txt")
        viewModel.replaceItems([renamed])
        #expect(viewModel.items.map(\.path) == ["/tmp/renamed.txt"])
    }
}
