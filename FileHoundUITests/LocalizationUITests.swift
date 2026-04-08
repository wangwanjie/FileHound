import XCTest

final class LocalizationUITests: XCTestCase {
    @MainActor
    func testLanguageSwitchAppliesWithoutRestart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        app.menuBars.menuBarItems["FileHound"].menus.menuItems["openPreferences:"].click()
        XCTAssertTrue(app.windows["偏好设置"].waitForExistence(timeout: 2))

        let languagePopup = app.popUpButtons["LanguagePopup"]
        XCTAssertTrue(languagePopup.waitForExistence(timeout: 2))
        languagePopup.click()
        app.menuItems["English"].click()

        XCTAssertTrue(app.staticTexts["Search Rules"].waitForExistence(timeout: 3))
    }
}
