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
        #expect(window.contentLayoutRect.width < 780)
        #expect(window.contentLayoutRect.height < 240)
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

    @MainActor
    @Test
    func reloadLocalizedContentDoesNotShiftWindowOrigin() throws {
        let controller = SearchWindowController()
        controller.showWindow(nil)
        let window = try #require(controller.window)
        let initialOrigin = NSPoint(x: 320, y: 420)
        window.setFrameOrigin(initialOrigin)

        controller.reloadLocalizedContent()

        #expect(window.frame.origin == initialOrigin)
    }

    @MainActor
    @Test
    func resizingRuleAreaPreservesWindowWidth() throws {
        let controller = SearchWindowController()
        controller.showWindow(nil)
        let window = try #require(controller.window)
        let initialWidth = window.frame.width
        let formController = try #require(window.contentViewController as? SearchFormViewController)

        controller.searchFormViewController(formController, desiredRulesContentHeight: 420)

        #expect(window.frame.width == initialWidth)
    }
}
