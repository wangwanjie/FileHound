import AppKit
import Testing
@testable import FileHound

@MainActor
struct SearchResultsWindowControllerTests {
    @Test
    func refreshRunsOnlyOnExplicitRequest() {
        var refreshCount = 0
        let controller = SearchResultsWindowController(
            viewModel: SearchResultsViewModel(),
            title: "Results",
            refreshHandler: { refreshCount += 1 }
        )

        controller.refreshSearchResults(nil)
        #expect(refreshCount == 1)

        let item = NSMenuItem(title: "", action: #selector(SearchResultsWindowController.refreshSearchResults(_:)), keyEquivalent: "")
        #expect(controller.validateMenuItem(item))
        let withoutHandler = SearchResultsWindowController(viewModel: SearchResultsViewModel(), title: "Results")
        #expect(withoutHandler.validateMenuItem(item) == false)
    }

    @Test
    func expandFoldersSettingCanChangeAfterCreation() {
        let controller = SearchResultsWindowController(viewModel: SearchResultsViewModel(), title: "Results")
        #expect(controller.expandsFoldersWhenShowingResults == false)
        controller.expandsFoldersWhenShowingResults = true
        #expect(controller.expandsFoldersWhenShowingResults)
    }

    @Test
    func streamingProgressKeepsUserRemovalsUntilNewSearch() {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "", previewSnippet: nil)
        let third = SearchResultItem(path: "/tmp/c.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        let controller = SearchResultsWindowController(viewModel: viewModel, title: "Results")

        controller.update(title: "Results", items: [first, second])
        viewModel.removeItems(ids: [first.id])

        // 同一次搜索的后续进度：被移除的项不能再出现，新结果照常加入
        controller.update(title: "Results", items: [first, second, third], startsNewSearch: false)
        #expect(viewModel.items.map(\.path) == ["/tmp/b.txt", "/tmp/c.txt"])

        // 新搜索开始后重新显示
        controller.update(title: "Results", items: [first, second, third], startsNewSearch: true)
        #expect(viewModel.items.map(\.path) == ["/tmp/a.txt", "/tmp/b.txt", "/tmp/c.txt"])
    }

    @Test
    func newSearchDiscardsTrashTrackingButProgressKeepsIt() {
        let item = SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        let controller = SearchResultsWindowController(viewModel: viewModel, title: "Results")
        controller.update(title: "Results", items: [item])
        viewModel.markItemsTrashed([TrashedResultEntry(item: item, trashedPath: "/Users/me/.Trash/a.txt")])

        controller.update(title: "Results", items: [item], startsNewSearch: false)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.trashedEntries.count == 1)

        controller.update(title: "Results", items: [item], startsNewSearch: true)
        #expect(viewModel.items.map(\.path) == ["/tmp/a.txt"])
        #expect(viewModel.trashedEntries.isEmpty)
    }

    @Test
    func shownWindowIsHeldUntilClosed() {
        SearchResultsWindowController.debugCloseAllOpenWindows()
        defer { SearchResultsWindowController.debugCloseAllOpenWindows() }

        let controller = SearchResultsWindowController(viewModel: SearchResultsViewModel(), title: "Results")
        controller.showWindow(nil)
        #expect(SearchResultsWindowController.debugOpenControllerCount == 1)

        controller.window?.close()
        #expect(SearchResultsWindowController.debugOpenControllerCount == 0)
    }
}
