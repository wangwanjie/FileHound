import AppKit
import Testing
@testable import FileHound

struct SearchWindowControllerTests {
    @MainActor
    @Test
    func createsCompactPrimaryWindow() {
        let controller = SearchWindowController()
        let window = try! #require(controller.window)

        #expect(window.title == "FileHound")
        #expect(window.contentLayoutRect.width <= 820)
        #expect(window.contentLayoutRect.height < 280)
    }

    @MainActor
    @Test
    func reopensClosedWindowUsingSameInstance() throws {
        let controller = SearchWindowController()

        controller.showWindow(nil)
        let initialWindow = try #require(controller.window)
        initialWindow.close()

        controller.showWindow(nil)

        #expect(controller.window === initialWindow)
        #expect(controller.window?.isVisible == true)
    }
}
