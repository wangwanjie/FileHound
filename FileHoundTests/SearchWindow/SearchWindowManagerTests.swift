import AppKit
import Testing
@testable import FileHound

struct SearchWindowManagerTests {
    @MainActor
    private func makeManager(orderedWindows: @escaping () -> [NSWindow] = { [] }) -> SearchWindowManager {
        SearchWindowManager(
            makeController: { SearchWindowController(restoresPreviousSession: $0) },
            orderedWindowsProvider: orderedWindows
        )
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
}
