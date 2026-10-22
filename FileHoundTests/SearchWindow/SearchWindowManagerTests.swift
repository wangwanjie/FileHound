import AppKit
import Testing
@testable import FileHound

struct SearchWindowManagerTests {
    /// 每个窗口使用独立的内存存储环境，不读写真实会话 / 历史
    @MainActor
    private func makeManager(orderedWindows: @escaping () -> [NSWindow] = { [] }) -> SearchWindowManager {
        SearchWindowManager(
            makeController: { SearchFormTestEnvironment().makeWindowController(restoresPreviousSession: $0) },
            orderedWindowsProvider: orderedWindows
        )
    }

    /// 让窗口进入「搜索中」：直接驱动表单状态，不启动真实搜索
    @MainActor
    private func simulateSearching(in controller: SearchWindowController) throws {
        let formController = try #require(controller.window?.contentViewController as? SearchFormViewController)
        formController.debugSimulateSearching()
        #expect(controller.isSearching)
    }

    @MainActor
    @Test
    func presentActiveWindowReusesExistingController() {
        let manager = makeManager()
        let first = manager.presentActiveWindow()
        let second = manager.presentActiveWindow()

        #expect(first === second)
        #expect(manager.controllers.count == 1)
        first.window?.close()
    }

    @MainActor
    @Test
    func openNewWindowKeepsExistingWindowsOpen() throws {
        let manager = makeManager()
        let first = manager.presentActiveWindow()
        let second = manager.openNewWindow()

        #expect(first !== second)
        #expect(manager.controllers.count == 2)
        #expect(first.window?.isVisible == true)
        #expect(second.window?.isVisible == true)

        let firstFrame = try #require(first.window?.frame)
        let secondFrame = try #require(second.window?.frame)
        #expect(firstFrame.origin != secondFrame.origin)

        manager.windows.forEach { $0.close() }
    }

    @MainActor
    @Test
    func closingWindowReleasesItWhenOthersRemainOpen() {
        let manager = makeManager()
        let first = manager.presentActiveWindow()
        let second = manager.openNewWindow()

        first.window?.close()

        #expect(manager.controllers.count == 1)
        #expect(manager.controllers.first === second)
        second.window?.close()
    }

    @MainActor
    @Test
    func closingLastWindowKeepsItForReopen() {
        let manager = makeManager()
        let controller = manager.presentActiveWindow()

        controller.window?.close()

        #expect(manager.controllers.count == 1)
        #expect(manager.presentActiveWindow() === controller)
        controller.window?.close()
    }

    @MainActor
    @Test
    func openNewWindowReleasesClosedIdleWindows() {
        let manager = makeManager()
        let closed = manager.presentActiveWindow()
        closed.window?.close()

        let fresh = manager.openNewWindow()

        #expect(manager.controllers.count == 1)
        #expect(manager.controllers.first === fresh)
        fresh.window?.close()
    }

    @MainActor
    @Test
    func activeControllerFollowsWindowOrderIncludingResultsWindows() throws {
        var orderedWindows: [NSWindow] = []
        let manager = makeManager(orderedWindows: { orderedWindows })
        let first = manager.presentActiveWindow()
        let second = manager.openNewWindow()

        orderedWindows = [try #require(first.window), try #require(second.window)]
        #expect(manager.activeController === first)

        orderedWindows = [try #require(second.window), try #require(first.window)]
        #expect(manager.activeController === second)

        manager.windows.forEach { $0.close() }
    }

    @MainActor
    @Test
    func snapshotReusesIdleActiveWindow() {
        let manager = makeManager()
        let active = manager.presentActiveWindow()

        #expect(manager.controllerForApplyingSnapshot() === active)
        active.window?.close()
    }

    @MainActor
    @Test
    func closingSearchingWindowCancelsItsSearchWhenOthersRemainOpen() throws {
        let manager = makeManager()
        let searching = manager.presentActiveWindow()
        let other = manager.openNewWindow()
        try simulateSearching(in: searching)

        searching.window?.close()

        #expect(manager.controllers.contains { $0 === searching } == false)
        #expect(searching.isSearching == false)
        other.window?.close()
    }

    @MainActor
    @Test
    func closingLastSearchingWindowKeepsSearchRunning() throws {
        let manager = makeManager()
        let controller = manager.presentActiveWindow()
        try simulateSearching(in: controller)

        controller.window?.close()

        // 最后一个窗口保留，搜索继续，结束后结果窗口照常打开
        #expect(manager.controllers.first === controller)
        #expect(controller.isSearching)
        controller.cancelSearchIfNeeded()
    }

    @MainActor
    @Test
    func snapshotOpensNewWindowWhenActiveWindowIsSearching() throws {
        let manager = makeManager()
        let active = manager.presentActiveWindow()
        try simulateSearching(in: active)

        let target = manager.controllerForApplyingSnapshot()

        #expect(target !== active)
        #expect(active.isSearching)
        #expect(manager.controllers.count == 2)
        active.cancelSearchIfNeeded()
        manager.windows.forEach { $0.close() }
    }
}
