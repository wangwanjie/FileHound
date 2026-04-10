import XCTest

final class UpdatePreferencesSmokeTests: XCTestCase {
    @MainActor
    func testUpdatesTabShowsPolicyPopupAndCheckNowButton() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting", "--open-preferences-on-launch", "--open-updates-preferences-on-launch"]
        app.launch()
        let window = app.windows["偏好设置"]
        XCTAssertTrue(window.waitForExistence(timeout: 3))

        XCTAssertTrue(window.popUpButtons["UpdatePolicyPopup"].waitForExistence(timeout: 2))
        XCTAssertTrue(window.buttons["CheckNowButton"].exists)
    }
}
