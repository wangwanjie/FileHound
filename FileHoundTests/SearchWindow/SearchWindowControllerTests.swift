import AppKit
import Testing
@testable import FileHound

struct SearchWindowControllerTests {
    @MainActor
    @Test
    func createsCompactPrimaryWindow() throws {
        // 内存存储中没有保存的会话，窗口按单条规则的默认高度创建
        let controller = SearchFormTestEnvironment().makeWindowController()
        let window = try #require(controller.window)
        defer { window.close() }

        #expect(window.title == "FileHound")
        #expect(window.contentLayoutRect.width < 780)
        #expect(window.contentLayoutRect.height < 240)
    }

    @MainActor
    @Test
    func reopensClosedWindowUsingSameInstance() throws {
        let controller = SearchFormTestEnvironment().makeWindowController()

        controller.showWindow(nil)
        let initialWindow = try #require(controller.window)
        defer { initialWindow.close() }
        initialWindow.close()

        controller.showWindow(nil)

        #expect(controller.window === initialWindow)
        #expect(controller.window?.isVisible == true)
    }

    @MainActor
    @Test
    func reloadLocalizedContentDoesNotShiftWindowOrigin() throws {
        let controller = SearchFormTestEnvironment().makeWindowController()
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let initialOrigin = NSPoint(x: 320, y: 420)
        window.setFrameOrigin(initialOrigin)

        controller.reloadLocalizedContent()

        #expect(window.frame.origin == initialOrigin)
    }

    @MainActor
    @Test
    func resizingRuleAreaPreservesWindowWidth() throws {
        let controller = SearchFormTestEnvironment().makeWindowController()
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let initialWidth = window.frame.width
        let formController = try #require(window.contentViewController as? SearchFormViewController)

        controller.searchFormViewController(formController, desiredRulesContentHeight: 420)

        #expect(window.frame.width == initialWidth)
    }

    @MainActor
    @Test
    func layoutUsesScreenOfTheWindow() throws {
        let controller = SearchFormTestEnvironment().makeWindowController()
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }

        // 默认布局以窗口所在屏幕为准，而不是固定使用主屏
        let screen = try #require(window.screen)
        #expect(SearchWindowController.visibleFrame(for: window) == screen.visibleFrame)
        #expect(SearchWindowController.visibleFrame(for: nil) == (NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)))
    }
}
