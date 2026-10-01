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

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        #expect(refreshCount == 0)

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
    func quitAfterLastWindowFollowsSetting() {
        let previous = AppSettings.shared.quitWhenAllWindowsAreClosed
        defer { AppSettings.shared.quitWhenAllWindowsAreClosed = previous }
        let delegate = AppDelegate()

        AppSettings.shared.quitWhenAllWindowsAreClosed = false
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp) == false)
        AppSettings.shared.quitWhenAllWindowsAreClosed = true
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }
}
