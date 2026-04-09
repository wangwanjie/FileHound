import AppKit
import Testing
@testable import FileHound

struct SearchFormViewControllerTests {
    @MainActor
    @Test
    func primaryActionEntersSearchingStateImmediately() {
        let controller = SearchFormViewController()
        _ = controller.view

        controller.debugTriggerPrimaryAction()

        #expect(controller.debugPrimaryActionTitle == "Stop")
        #expect(controller.debugStatusText == "Searching: Macintosh HD")
    }
}
