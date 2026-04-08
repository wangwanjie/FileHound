import XCTest

final class UpdatePreferencesSmokeTests: XCTestCase {
    @MainActor
    func testUpdateTabShowsCheckForUpdatesButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        app.menuBars.menuBarItems["FileHound"].menus.menuItems["openPreferences:"].click()
        app.buttons["更新"].click()

        XCTAssertTrue(app.buttons["检查更新"].waitForExistence(timeout: 2))
    }
}
