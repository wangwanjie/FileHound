import XCTest

final class PreferencesUITests: XCTestCase {
    @MainActor
    func testPreferencesShowsSegmentedTabsAndAppearanceControls() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting", "--open-preferences-on-launch"]
        app.launch()

        let window = app.windows["偏好设置"]
        XCTAssertTrue(window.waitForExistence(timeout: 3))
        XCTAssertTrue(window.popUpButtons["ThemePopup"].exists)
        XCTAssertTrue(window.popUpButtons["LanguagePopup"].exists)
        XCTAssertTrue(window.textFields["ResultsFontSizeField"].exists)
        XCTAssertTrue(window.buttons["DimColorButton"].exists)
    }
}
