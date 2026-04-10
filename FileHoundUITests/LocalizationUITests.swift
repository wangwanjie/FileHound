import XCTest

final class LocalizationUITests: XCTestCase {
    @MainActor
    func testLanguageSwitchAppliesWithoutRestart() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting", "--fixture-results", "--show-secondary-preferences-on-launch"]
        app.launch()

        let preferencesWindow = app.windows["偏好设置"]
        XCTAssertTrue(preferencesWindow.waitForExistence(timeout: 2))

        let languagePopup = preferencesWindow.popUpButtons["LanguagePopup"]
        XCTAssertTrue(languagePopup.waitForExistence(timeout: 2))
        languagePopup.click()
        app.menuItems["English"].click()

        XCTAssertTrue(app.windows["FileHound"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Find Items"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.windows["Name contains report"].exists)
    }
}
