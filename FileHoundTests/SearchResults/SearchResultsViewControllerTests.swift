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

    @MainActor
    @Test
    func gridModeShowsPreviewAndSortControlsAndTracksSelectedMode() {
        let viewModel = SearchResultsViewModel()
        viewModel.items = [
            SearchResultItem(path: "/tmp/report.txt", matchReason: "名称命中", previewSnippet: nil)
        ]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        #expect(controller.debugSelectedMode == .grid)
        #expect(controller.debugShowsPreviewSlider == true)
        #expect(controller.debugShowsSortPopup == true)

        viewModel.mode = .table

        #expect(controller.debugSelectedMode == .table)
        #expect(controller.debugShowsPreviewSlider == false)
        #expect(controller.debugShowsSortPopup == false)
    }

    @MainActor
    @Test
    func previewSizeChangesGridLayoutSize() {
        let viewModel = SearchResultsViewModel()
        viewModel.items = [
            SearchResultItem(path: "/tmp/report.txt", matchReason: "名称命中", previewSnippet: nil)
        ]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        let initialSize = controller.debugGridItemSize
        controller.debugSetPreviewSize(112)

        #expect(controller.debugGridItemSize.width > initialSize.width)
        #expect(controller.debugGridItemSize.height > initialSize.height)
    }

    @MainActor
    @Test
    func showsMatchCountAndSelectedPathInStatusBar() {
        let selectedItem = SearchResultItem(
            path: "/Users/VanJay/Documents/report.txt",
            matchReason: "名称命中",
            previewSnippet: nil
        )
        let otherItem = SearchResultItem(path: "/Users/VanJay/Documents/archive.txt", matchReason: "名称命中", previewSnippet: nil)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [selectedItem, otherItem]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        #expect(controller.debugMatchCountValue == 2)

        viewModel.selectedItem = selectedItem

        #expect(controller.debugSelectedPathComponents == ["Users", "VanJay", "Documents", "report.txt"])
    }
}
