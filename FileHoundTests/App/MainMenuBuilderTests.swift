import AppKit
import Testing
@testable import FileHound

struct MainMenuBuilderTests {
    @MainActor
    @Test
    func buildAddsEditMenuWithTextCommands() {
        let menu = MainMenuBuilder().build()

        #expect(menu.items.count == 2)

        let editMenu = try! #require(menu.item(at: 1)?.submenu)
        #expect(editMenu.items.contains { $0.action == #selector(NSText.copy(_:)) })
        #expect(editMenu.items.contains { $0.action == #selector(NSText.paste(_:)) })
        #expect(editMenu.items.contains { $0.action == #selector(NSText.selectAll(_:)) })
    }
}
