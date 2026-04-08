import XCTest

final class SearchResultsUITests: XCTestCase {
    @MainActor
    func testSwitchesBetweenListAndTreeModes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--fixture-results"]
        app.launch()

        app.buttons["树形视图"].click()

        let resultLabel = app.staticTexts["report.txt"]
        XCTAssertTrue(resultLabel.waitForExistence(timeout: 2))
        resultLabel.click()

        XCTAssertTrue(app.staticTexts["内容命中"].waitForExistence(timeout: 2))
    }
}
