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
}
