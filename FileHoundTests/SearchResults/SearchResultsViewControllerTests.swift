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
        #expect(controller.debugShowsSortPopup == true)
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

    @MainActor
    @Test
    func toolbarButtonsExposeTooltipsAndFilterFlags() {
        let visible = SearchResultItem(path: "/tmp/report.txt", matchReason: "名称命中", previewSnippet: nil)
        let hidden = SearchResultItem(path: "/tmp/.hidden.txt", matchReason: "名称命中", previewSnippet: nil, isInvisible: true)
        let package = SearchResultItem(path: "/tmp/Demo.app", matchReason: "名称命中", previewSnippet: nil, isPackage: true)
        let trashed = SearchResultItem(path: "/tmp/trash.txt", matchReason: "名称命中", previewSnippet: nil, isTrashed: true)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [visible, hidden, package, trashed]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        #expect(controller.debugToolbarTooltips.allSatisfy { $0.isEmpty == false })
        #expect(viewModel.projectedItems.count == 1)

        controller.debugToggleInvisibles()
        controller.debugTogglePackages()
        controller.debugToggleTrashed()

        #expect(viewModel.showInvisibleItems == true)
        #expect(viewModel.showPackageContents == true)
        #expect(viewModel.showTrashedItems == true)
        #expect(viewModel.projectedItems.count == 4)
    }

    @MainActor
    @Test
    func highlightsNameAndExtensionMatchesInDisplayName() {
        let nameItem = SearchResultItem(
            path: "/tmp/report.lookin",
            matchReason: "名称命中",
            previewSnippet: "report",
            highlightKind: .name,
            highlightQuery: "report"
        )
        let extensionItem = SearchResultItem(
            path: "/tmp/report.lookin",
            matchReason: "扩展名命中",
            previewSnippet: "lookin",
            highlightKind: .extensionName,
            highlightQuery: "lookin"
        )

        let nameText = SearchResultNameHighlighter.attributedTitle(for: nameItem, baseColor: .labelColor)
        let extensionText = SearchResultNameHighlighter.attributedTitle(for: extensionItem, baseColor: .labelColor)

        #expect(nameText.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
        #expect(extensionText.attribute(.backgroundColor, at: 7, effectiveRange: nil) != nil)
    }

    @MainActor
    @Test
    func exposesFullSortFieldListInToolbar() {
        let viewModel = SearchResultsViewModel()
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        #expect(controller.debugSortTitles == [
            "Name",
            "Date Modified",
            "Date Created",
            "Last Opened",
            "Date Added",
            "Kind",
            "Size",
            "Tags",
            "Enclosing Folder",
            "Path"
        ])
    }

    @MainActor
    @Test
    func tableAndTreeRowsKeepTextCenteredWithIcons() {
        let item = SearchResultItem(path: "/tmp/report.lookin", matchReason: "名称命中", previewSnippet: "report")
        let tableController = ResultsTableViewController()
        let outlineController = ResultsOutlineViewController()
        _ = tableController.view
        _ = outlineController.view

        #expect(tableController.debugRowHeight >= 24)
        #expect(outlineController.debugRowHeight >= 24)
        #expect(tableController.debugNameCellAlignmentOffset(for: item) < 2)
        #expect(outlineController.debugNameCellAlignmentOffset(for: item) < 2)
    }

    @MainActor
    @Test
    func gridTitlesStayHorizontallyCenteredAcrossPreviewSizes() {
        let item = SearchResultItem(
            path: "/tmp/2026-quarterly-preview-alignment-report.lookin",
            matchReason: "名称命中",
            previewSnippet: "report",
            highlightKind: .name,
            highlightQuery: "report"
        )
        let viewModel = SearchResultsViewModel()
        viewModel.items = [item]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        #expect(controller.debugGridTitleParagraphAlignment(for: item, previewSize: 72) == .center)
        #expect(controller.debugGridTitleAlignmentOffset(for: item, previewSize: 72) < 2)
        #expect(controller.debugGridTitleAlignmentOffset(for: item, previewSize: 112) < 2)
    }

    @MainActor
    @Test
    func gridTitlesKeepTwoLineMiddleTruncation() {
        let item = SearchResultItem(
            path: "/tmp/this-is-a-very-very-long-file-name-used-to-lock-grid-preview-caption-behavior.lookin",
            matchReason: "名称命中",
            previewSnippet: "preview",
            highlightKind: .name,
            highlightQuery: "preview"
        )
        let controller = SearchResultsViewController(viewModel: SearchResultsViewModel())
        _ = controller.view

        #expect(controller.debugGridTitleMaximumNumberOfLines == 2)
        #expect(controller.debugGridTitleLineBreakMode == .byTruncatingMiddle)
        #expect(controller.debugGridTitleAlignmentOffset(for: item, previewSize: 48) < 2)
    }

    @MainActor
    @Test
    func treeViewBuildsFolderHierarchyInsteadOfFlatList() {
        let outlineController = ResultsOutlineViewController()
        _ = outlineController.view

        outlineController.update(items: [
            SearchResultItem(path: "/Users/test/demo/report.txt", matchReason: "名称命中", previewSnippet: "report", kind: "Text Document"),
            SearchResultItem(path: "/Users/test/demo/assets/22222.png", matchReason: "名称命中", previewSnippet: "22222", kind: "PNG Image")
        ])

        let rows = outlineController.debugTreeRows

        #expect(rows.contains { $0.title == "demo" && $0.depth == 0 && $0.isMatchedResult == false })
        #expect(rows.contains { $0.title == "report.txt" && $0.depth == 1 && $0.isMatchedResult == true })
        #expect(rows.contains { $0.title == "assets" && $0.depth == 1 && $0.isMatchedResult == false })
        #expect(rows.contains { $0.title == "22222.png" && $0.depth == 2 && $0.isMatchedResult == true })
    }

    @MainActor
    @Test
    func treeViewExpandsFoldersToMatchedFileLayerByDefault() {
        let outlineController = ResultsOutlineViewController()
        _ = outlineController.view

        outlineController.update(items: [
            SearchResultItem(path: "/Users/test/demo/report.txt", matchReason: "名称命中", previewSnippet: "report", kind: "Text Document"),
            SearchResultItem(path: "/Users/test/demo/assets/22222.png", matchReason: "名称命中", previewSnippet: "22222", kind: "PNG Image")
        ])

        #expect(outlineController.debugExpandedTitles.contains("demo"))
        #expect(outlineController.debugExpandedTitles.contains("assets"))
    }

    @MainActor
    @Test
    func resultsBackgroundsRefreshAcrossAppearances() {
        let controller = SearchResultsViewController(viewModel: SearchResultsViewModel())
        _ = controller.view

        let lightRoot = controller.debugRootBackgroundHex(for: .aqua)
        let darkRoot = controller.debugRootBackgroundHex(for: .darkAqua)
        let lightToolbar = controller.debugToolbarBackgroundHex(for: .aqua)
        let darkToolbar = controller.debugToolbarBackgroundHex(for: .darkAqua)
        let lightStatus = controller.debugStatusBackgroundHex(for: .aqua)
        let darkStatus = controller.debugStatusBackgroundHex(for: .darkAqua)

        #expect(lightRoot != darkRoot)
        #expect(lightToolbar != darkToolbar)
        #expect(lightStatus != darkStatus)
    }
}
