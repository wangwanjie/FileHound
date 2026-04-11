import XCTest

final class SearchHistoryUITests: XCTestCase {
    @MainActor
    func testSeededSavedSearchRestoresCriteriaIntoFindWindow() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = [
            "--uitesting",
            "--seed-fixture-saved-search",
            "--open-seeded-saved-search-on-launch"
        ]
        app.launch()

        let scopePopup = app.popUpButtons["SearchScopePopup"]
        let valueField = app.textFields["SearchRuleValueField"]

        XCTAssertTrue(scopePopup.waitForExistence(timeout: 3))
        XCTAssertTrue(valueField.waitForExistence(timeout: 3))

        XCTAssertTrue(String(describing: scopePopup.value ?? "").contains("Fixtures"))
        XCTAssertEqual(valueField.value as? String, "fixture-report")
    }
}
