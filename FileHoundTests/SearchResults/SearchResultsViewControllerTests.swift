import AppKit
import Combine
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
    func statusBarReflectsSearchInProgressAndCompletion() {
        let viewModel = SearchResultsViewModel()
        viewModel.searchStatus = .searching
        viewModel.items = [
            SearchResultItem(path: "/tmp/report.txt", matchReason: "名称命中", previewSnippet: nil)
        ]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        #expect(controller.debugShowsSearchActivity == true)
        #expect(controller.debugStatusText == L10n.format("results.status.searching", 1))

        viewModel.items += [
            SearchResultItem(path: "/tmp/archive.txt", matchReason: "名称命中", previewSnippet: nil)
        ]
        #expect(controller.debugStatusText == L10n.format("results.status.searching", 2))

        viewModel.searchStatus = .finished
        #expect(controller.debugShowsSearchActivity == false)
        #expect(controller.debugStatusText == L10n.format("results.status.matched", 2))

        viewModel.searchStatus = .stopped
        #expect(controller.debugStatusText == L10n.format("results.status.stopped", 2))
    }

    @MainActor
    @Test
    func hidesEmptyStateWhileSearchIsInProgress() {
        let viewModel = SearchResultsViewModel()
        viewModel.searchStatus = .searching
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        #expect(controller.debugShowsEmptyState == false)

        viewModel.searchStatus = .finished

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
        let package = SearchResultItem(path: "/tmp/Demo.app/Contents/Info.plist", matchReason: "名称命中", previewSnippet: nil)
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
            "name", "modified", "created", "last_opened", "added",
            "kind", "size", "tags", "enclosing_folder", "path"
        ].map { L10n.string("results.column.\($0)") })
    }

    @MainActor
    @Test
    func selectionActionsValidateAndCopyFileURLs() throws {
        let viewModel = SearchResultsViewModel()
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: "")
        let second = SearchResultItem(path: "/tmp/b c.txt", matchReason: "", previewSnippet: "")
        viewModel.items = [first, second]
        viewModel.mode = .table
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        let openItem = NSMenuItem(title: "", action: #selector(SearchResultsViewController.openSelectedResults(_:)), keyEquivalent: "")
        let trashItem = NSMenuItem(title: "", action: #selector(SearchResultsViewController.moveSelectedResultsToTrash(_:)), keyEquivalent: "")
        let copyItem = NSMenuItem(title: "", action: #selector(SearchResultsViewController.copy(_:)), keyEquivalent: "")
        #expect(controller.validateMenuItem(openItem) == false)
        #expect(controller.validateMenuItem(trashItem) == false)
        #expect(controller.validateMenuItem(copyItem) == false)

        // 通过列表视图选中（与键盘 ⌘A 相同的路径），而不是直接改视图模型
        controller.debugTableController.debugTableView.selectAll(nil)
        #expect(Set(viewModel.selectedIDs) == [first.id, second.id])
        #expect(controller.validateMenuItem(openItem))
        #expect(controller.validateMenuItem(trashItem))
        #expect(controller.validateMenuItem(copyItem))

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("FileHoundTests.copy.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(controller.writeSelectedItems(to: pasteboard))
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(urls?.map(\.path) == ["/tmp/a.txt", "/tmp/b c.txt"])
        #expect(pasteboard.string(forType: .string) == "/tmp/a.txt\n/tmp/b c.txt")
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
    func resultsBackgroundLayersRefreshAcrossAppearances() throws {
        let controller = SearchResultsViewController(viewModel: SearchResultsViewModel())
        _ = controller.view
        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))

        // 读取切换外观后各视图 layer 上实际设置的颜色，而不是只解析颜色常量
        let light = controller.debugLayerBackgroundColors(appearanceName: .aqua)
        #expect(light.root == NSColor.fhWindowSurface(for: aqua).fhResolvedCGColor(for: aqua))
        #expect(light.toolbar == NSColor.fhPanelSurface(for: aqua, alpha: 0.94).fhResolvedCGColor(for: aqua))
        #expect(light.status == NSColor.fhPanelSurface(for: aqua, alpha: 0.96).fhResolvedCGColor(for: aqua))

        let dark = controller.debugLayerBackgroundColors(appearanceName: .darkAqua)
        #expect(dark.root == NSColor.fhWindowSurface(for: darkAqua).fhResolvedCGColor(for: darkAqua))
        #expect(dark.toolbar == NSColor.fhPanelSurface(for: darkAqua, alpha: 0.94).fhResolvedCGColor(for: darkAqua))
        #expect(dark.status == NSColor.fhPanelSurface(for: darkAqua, alpha: 0.96).fhResolvedCGColor(for: darkAqua))
        #expect(light.root != dark.root)
        #expect(light.toolbar != dark.toolbar)
        #expect(light.status != dark.status)
    }

    @MainActor
    @Test
    func gridSelectionColorsResolveAgainstCurrentAppearance() throws {
        let controller = ResultsCollectionViewController()
        _ = controller.view

        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            let colors = controller.debugSelectedGridColors(appearanceName: name)
            #expect(colors.overlay == NSColor.controlAccentColor.withAlphaComponent(0.18).fhResolvedCGColor(for: appearance))
            #expect(colors.border == NSColor.controlAccentColor.fhResolvedCGColor(for: appearance))
        }
    }

    // MARK: - 选中同步

    @MainActor
    @Test
    func tableKeyboardSelectionAndSelectAllSyncToViewModel() {
        let items = (0..<3).map { SearchResultItem(path: "/tmp/\($0).txt", matchReason: "", previewSnippet: nil) }
        let viewModel = SearchResultsViewModel()
        viewModel.items = items
        viewModel.mode = .table
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view
        let tableView = controller.debugTableController.debugTableView

        // 键盘 ↑↓ 由表格内部调用 selectRowIndexes，不会发送 action
        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(viewModel.selectedItems.map(\.path) == ["/tmp/1.txt"])
        #expect(viewModel.selectedItem?.path == "/tmp/1.txt")

        tableView.selectAll(nil)
        #expect(viewModel.selectedItems.count == 3)

        tableView.deselectAll(nil)
        #expect(viewModel.selectedItems.isEmpty)
        #expect(viewModel.selectedItem == nil)
    }

    @MainActor
    @Test
    func gridAndTreeSelectAllSyncToViewModel() {
        let items = [
            SearchResultItem(path: "/tmp/demo/a.txt", matchReason: "", previewSnippet: nil),
            SearchResultItem(path: "/tmp/demo/b.txt", matchReason: "", previewSnippet: nil)
        ]
        let viewModel = SearchResultsViewModel()
        viewModel.items = items
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        controller.debugGridController.debugCollectionView.selectAll(nil)
        #expect(controller.debugGridController.debugCollectionView.selectionIndexPaths.count == 2)
        #expect(Set(viewModel.selectedItems.map(\.path)) == ["/tmp/demo/a.txt", "/tmp/demo/b.txt"])

        viewModel.mode = .tree
        let outlineView = controller.debugTreeController.debugOutlineView
        outlineView.deselectAll(nil)
        #expect(viewModel.selectedItems.isEmpty)
        outlineView.selectAll(nil)
        #expect(Set(viewModel.selectedItems.map(\.path)) == ["/tmp/demo/a.txt", "/tmp/demo/b.txt"])
    }

    @MainActor
    @Test
    func switchingModesPushesSelectionAndHiddenViewsCannotOverrideIt() {
        let a = SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: nil)
        let b = SearchResultItem(path: "/tmp/b.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [a, b]
        viewModel.mode = .table
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view
        let tableView = controller.debugTableController.debugTableView
        let collectionView = controller.debugGridController.debugCollectionView

        tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(viewModel.selectedItems == [b])

        // 切换到网格：选中跟随视图模型
        viewModel.mode = .grid
        #expect(collectionView.selectionIndexPaths == [IndexPath(item: 1, section: 0)])

        collectionView.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        #expect(viewModel.selectedItems == [a])

        // 结果刷新（如流式进度、过滤）后，隐藏的列表视图不能用旧选中 b 覆盖视图模型
        viewModel.items += [SearchResultItem(path: "/tmp/c.txt", matchReason: "", previewSnippet: nil)]
        viewModel.filterText = "txt"
        #expect(viewModel.selectedItems == [a])

        // 切回列表：显示视图模型的选中 a，并包含刷新后的新结果
        viewModel.mode = .table
        #expect(tableView.numberOfRows == 3)
        #expect(tableView.selectedRowIndexes == IndexSet(integer: 0))
        #expect(viewModel.selectedItems == [a])
    }

    @MainActor
    @Test
    func onlyVisibleViewIsRefreshedUntilModeSwitch() {
        let viewModel = SearchResultsViewModel()
        viewModel.items = [SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: nil)]
        viewModel.mode = .grid
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view
        let tableView = controller.debugTableController.debugTableView

        viewModel.items += [SearchResultItem(path: "/tmp/b.txt", matchReason: "", previewSnippet: nil)]
        #expect(controller.debugGridController.debugCollectionView.numberOfItems(inSection: 0) == 2)
        #expect(tableView.numberOfRows == 0)

        viewModel.mode = .table
        #expect(tableView.numberOfRows == 2)
    }

    // MARK: - 树视图

    @MainActor
    @Test
    func treeViewUsesLongestCommonPrefixForDivergingPaths() {
        let outlineController = ResultsOutlineViewController()
        _ = outlineController.view

        outlineController.update(items: [
            SearchResultItem(path: "/Users/me/p1/src/a.txt", matchReason: "", previewSnippet: nil),
            SearchResultItem(path: "/Users/me/p2/src/b.txt", matchReason: "", previewSnippet: nil)
        ])

        let paths = outlineController.debugTreePaths
        #expect(paths.first?.path == "/Users/me")
        #expect(paths.first?.depth == 0)
        #expect(paths.contains { $0.path == "/Users/me/p1/src/a.txt" && $0.depth == 3 })
        #expect(paths.contains { $0.path == "/Users/me/p2/src/b.txt" && $0.depth == 3 })
        #expect(paths.contains { $0.path == "/Users/me/src" } == false)
    }

    @MainActor
    @Test
    func treeViewKeepsUserCollapsedFoldersAcrossRefreshes() {
        let outlineController = ResultsOutlineViewController()
        _ = outlineController.view
        let report = SearchResultItem(path: "/Users/test/demo/report.txt", matchReason: "", previewSnippet: nil)
        let image = SearchResultItem(path: "/Users/test/demo/assets/1.png", matchReason: "", previewSnippet: nil)
        outlineController.update(items: [report, image])
        #expect(outlineController.debugExpandedTitles.contains("assets"))

        outlineController.debugCollapse(title: "assets")
        #expect(outlineController.debugExpandedTitles.contains("assets") == false)

        outlineController.update(items: [
            report,
            image,
            SearchResultItem(path: "/Users/test/demo/assets/2.png", matchReason: "", previewSnippet: nil),
            SearchResultItem(path: "/Users/test/demo/docs/x.txt", matchReason: "", previewSnippet: nil)
        ])

        // 用户折叠的保持折叠，新出现的文件夹按默认规则展开
        #expect(outlineController.debugExpandedTitles.contains("assets") == false)
        #expect(outlineController.debugExpandedTitles.contains("demo"))
        #expect(outlineController.debugExpandedTitles.contains("docs"))

        // 折叠父文件夹再展开，子文件夹恢复之前的展开状态
        outlineController.debugCollapse(title: "demo")
        outlineController.debugExpand(title: "demo")
        #expect(outlineController.debugExpandedTitles.contains("docs"))
        #expect(outlineController.debugExpandedTitles.contains("assets") == false)
    }

    @MainActor
    @Test(arguments: [false, true])
    func expandFoldersPreferenceControlsMatchedFolders(expandsAll: Bool) {
        let outlineController = ResultsOutlineViewController()
        _ = outlineController.view
        outlineController.expandsFoldersOnReload = expandsAll

        outlineController.update(items: [
            SearchResultItem(path: "/tmp/root/folder", matchReason: "", previewSnippet: nil),
            SearchResultItem(path: "/tmp/root/folder/inner.txt", matchReason: "", previewSnippet: nil),
            SearchResultItem(path: "/tmp/root/other/b.txt", matchReason: "", previewSnippet: nil)
        ])

        // 补出的上级文件夹总是展开到匹配结果所在层级；匹配到的文件夹只在偏好开启时展开
        #expect(outlineController.debugExpandedTitles.contains("root"))
        #expect(outlineController.debugExpandedTitles.contains("other"))
        #expect(outlineController.debugExpandedTitles.contains("folder") == expandsAll)
    }

    @MainActor
    @Test
    func syntheticTreeNodesDisableDestructiveMenuItemsAndCannotBeDragged() throws {
        let report = SearchResultItem(path: "/Users/test/demo/report.txt", matchReason: "", previewSnippet: nil)
        let image = SearchResultItem(path: "/Users/test/demo/assets/1.png", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [report, image]
        viewModel.mode = .tree
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view
        let treeController = controller.debugTreeController

        #expect(treeController.debugPasteboardURL(forTitle: "demo") == nil)
        #expect(treeController.debugPasteboardURL(forTitle: "report.txt")?.path == report.path)

        // 合成节点不在视图模型的结果中
        let synthetic = SearchResultItem(path: "/Users/test/demo", matchReason: "", previewSnippet: nil)
        let menu = try #require(controller.debugContextMenu(for: [synthetic]))
        #expect(menu.autoenablesItems == false)
        let disabledKeys = [
            "results.menu.move_to_trash", "results.menu.delete_immediately", "results.menu.rename",
            "results.menu.make_invisible", "results.menu.make_visible", "results.menu.unlock",
            "results.menu.set_label", "results.menu.remove_from_results"
        ]
        for key in disabledKeys {
            if let item = menu.item(withTitle: L10n.string(key)) {
                #expect(item.isEnabled == false, "\(key) 应禁用")
            }
        }
        #expect(menu.item(withTitle: L10n.string("results.menu.move_to_trash")) != nil)
        #expect(menu.item(withTitle: L10n.string("results.menu.reveal_in_finder"))?.isEnabled == true)

        let matchedMenu = try #require(controller.debugContextMenu(for: [report]))
        #expect(matchedMenu.item(withTitle: L10n.string("results.menu.move_to_trash"))?.isEnabled == true)
        #expect(matchedMenu.item(withTitle: L10n.string("results.menu.rename"))?.isEnabled == true)
    }

    // MARK: - 操作

    @MainActor
    @Test
    func cancellingDeleteConfirmationKeepsResults() {
        let item = SearchResultItem(path: "/tmp/never-deleted-\(UUID().uuidString).txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [item]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view
        var requests: [ResultConfirmationRequest] = []
        controller.confirmationOverride = { request in
            requests.append(request)
            return false
        }

        controller.debugDeleteImmediately(items: [item])

        #expect(requests == [.deleteImmediately(items: [item])])
        #expect(viewModel.items == [item])
    }

    @MainActor
    @Test
    func sortPopupKeepsOrderAndUnsupportedFieldsClearHeaderArrows() {
        let viewModel = SearchResultsViewModel()
        viewModel.items = [SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: nil)]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view
        viewModel.sortOrder = .descending

        controller.debugSelectSortFieldFromPopup(.size)
        #expect(viewModel.sortField == .size)
        #expect(viewModel.sortOrder == .descending)
        #expect(controller.debugTableController.debugSortDescriptorKeys == ["size"])
        #expect(controller.debugTreeController.debugSortDescriptorKeys == ["size"])

        controller.debugSelectSortFieldFromPopup(.path)
        #expect(viewModel.sortField == .path)
        #expect(controller.debugTableController.debugSortDescriptorKeys.isEmpty)
        #expect(controller.debugTreeController.debugSortDescriptorKeys.isEmpty)
    }

    @MainActor
    @Test
    func highlightRangesUseUTF16OffsetsForEmoji() {
        let item = SearchResultItem(
            path: "/tmp/😀👍 report.txt",
            matchReason: "",
            previewSnippet: nil,
            highlightKind: .name,
            highlightQuery: "report"
        )

        let text = SearchResultNameHighlighter.attributedTitle(for: item, baseColor: .labelColor)
        let expected = (text.string as NSString).range(of: "report")
        var effectiveRange = NSRange()
        let attribute = text.attribute(.backgroundColor, at: expected.location, effectiveRange: &effectiveRange)

        // 😀 与 👍 各占 2 个 UTF-16 码元，加上空格后 "report" 从第 5 位开始
        #expect(expected.location == 5)
        #expect(attribute != nil)
        #expect(effectiveRange == expected)
        #expect(text.attribute(.backgroundColor, at: expected.location - 1, effectiveRange: nil) == nil)

        let extensionItem = SearchResultItem(
            path: "/tmp/😀.lookin",
            matchReason: "",
            previewSnippet: nil,
            highlightKind: .extensionName,
            highlightQuery: ".lookin"
        )
        let extensionText = SearchResultNameHighlighter.attributedTitle(for: extensionItem, baseColor: .labelColor)
        var extensionRange = NSRange()
        _ = extensionText.attribute(.backgroundColor, at: 3, effectiveRange: &extensionRange)
        #expect(extensionRange == NSRange(location: 3, length: 6))
    }

    // MARK: - 本地化与无障碍

    @MainActor
    @Test
    func languageChangeReloadsResultsWindowStrings() {
        let subject = CurrentValueSubject<AppLanguage, Never>(.system)
        let controller = SearchResultsViewController(
            viewModel: SearchResultsViewModel(),
            localizationPublisher: subject.eraseToAnyPublisher()
        )
        _ = controller.view
        // 订阅时收到的当前语言不触发刷新
        #expect(controller.localizationReloadCount == 0)
        #expect(controller.debugPreviewLabelText == L10n.string("results.toolbar.preview_size"))

        subject.send(.en)
        #expect(controller.localizationReloadCount == 1)
        #expect(controller.debugEmptyStateText == L10n.string("results.empty"))
        #expect(controller.debugTableController.debugColumnTitles.first == L10n.string("results.column.name"))
        #expect(controller.debugSortTitles.first == L10n.string("results.column.name"))
    }

    @MainActor
    @Test
    func toolbarAccessibilityLabelsAreLocalizedAndIdentifiersStay() {
        let controller = SearchResultsViewController(viewModel: SearchResultsViewModel())
        _ = controller.view

        let labels = controller.debugToolbarAccessibilityLabels
        #expect(labels["ResultsModeGridButton"] == L10n.string("results.toolbar.grid"))
        #expect(labels["ResultsModeTableButton"] == L10n.string("results.mode.list"))
        #expect(labels["ResultsModeTreeButton"] == L10n.string("results.mode.tree"))
        #expect(labels["ResultsShowInvisiblesButton"] == L10n.string("results.toolbar.show_invisibles"))
        #expect(labels["ResultsShowPackagesButton"] == L10n.string("results.toolbar.show_package_contents"))
        #expect(labels["ResultsShowTrashedButton"] == L10n.string("results.toolbar.show_trashed"))
    }

    // MARK: - 拖出与导出

    @MainActor
    @Test
    func tableAndGridProvideFileURLsForDragging() {
        let item = SearchResultItem(path: "/tmp/b c.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [item]
        viewModel.mode = .table
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        #expect(controller.debugTableController.debugPasteboardURL(forRow: 0)?.path == "/tmp/b c.txt")
        #expect(controller.debugTableController.debugPasteboardURL(forRow: 5) == nil)

        viewModel.mode = .grid
        #expect(controller.debugGridController.debugPasteboardURL(forItem: 0)?.path == "/tmp/b c.txt")
    }

    @Test
    func dragOperationsDefaultToCopyAndMoveWithCommand() {
        #expect(ResultDragOperationPolicy.sourceOperationMask(for: .outsideApplication, modifierFlags: []) == [.copy, .link])
        #expect(ResultDragOperationPolicy.sourceOperationMask(for: .outsideApplication, modifierFlags: [.command]).contains(.move))
        #expect(ResultDragOperationPolicy.sourceOperationMask(for: .outsideApplication, modifierFlags: []).contains(.move) == false)
        #expect(ResultDragOperationPolicy.sourceOperationMask(for: .withinApplication, modifierFlags: []) == [])
    }

    @MainActor
    @Test
    func exportIsDisabledWithoutProjectedResults() {
        let viewModel = SearchResultsViewModel()
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view
        let exportItem = NSMenuItem(title: "", action: #selector(SearchResultsViewController.exportSearchResults(_:)), keyEquivalent: "")

        #expect(controller.validateMenuItem(exportItem) == false)
        #expect(controller.debugExportButtonEnabled == false)

        viewModel.items = [SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: nil)]
        #expect(controller.validateMenuItem(exportItem))
        #expect(controller.debugExportButtonEnabled)

        // 过滤后没有可导出的结果
        viewModel.filterText = "nothing-matches"
        #expect(controller.validateMenuItem(exportItem) == false)
        #expect(controller.debugExportButtonEnabled == false)
    }
}
