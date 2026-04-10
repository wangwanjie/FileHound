import AppKit
import Testing
@testable import FileHound

struct SearchResultsViewControllerTests {
    @MainActor
    @Test
    func showsEmptyStateWhenProjectedItemsBecomeEmpty() {
        let viewModel = SearchResultsViewModel()
        viewModel.items = [
            SearchResultItem(path: "/tmp/report.txt", matchReason: "名称命中", previewSnippet: nil)
        ]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        #expect(controller.debugShowsEmptyState == false)

        viewModel.items = []

        #expect(controller.debugShowsEmptyState == true)
    }
}
