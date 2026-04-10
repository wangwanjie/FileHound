import AppKit
import Testing
@testable import FileHound

struct PreferencesWindowControllerTests {
    @MainActor
    @Test
    func createsCompactNonResizableWindow() {
        let controller = PreferencesWindowController()
        let window = try! #require(controller.window)

        #expect(window.styleMask.contains(.resizable) == false)
        #expect(window.contentLayoutRect.width < 700)
        #expect(window.contentLayoutRect.height < 500)
    }
}
