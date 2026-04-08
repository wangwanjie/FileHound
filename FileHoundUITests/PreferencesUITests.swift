import XCTest

final class PreferencesUITests: XCTestCase {
    @MainActor
    func testPreferencesShowsAppearanceAndSearchTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        app.menuBars.menuBarItems["FileHound"].menus.menuItems["设置…"].click()

        XCTAssertTrue(app.windows["偏好设置"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["外观"].exists)
        XCTAssertTrue(app.buttons["搜索"].exists)
    }
}
