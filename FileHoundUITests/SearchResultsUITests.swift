import XCTest

final class SearchResultsUITests: XCTestCase {
    @MainActor
    func testSwitchesBetweenGridTableAndTreeModes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--fixture-results"]
        app.launch()

        XCTAssertTrue(app.buttons["ResultsModeGridButton"].waitForExistence(timeout: 5))

        app.buttons["ResultsModeTableButton"].click()
        XCTAssertTrue(app.tables["ResultsTable"].waitForExistence(timeout: 2))

        app.buttons["ResultsModeTreeButton"].click()
        XCTAssertTrue(app.outlines["ResultsOutline"].waitForExistence(timeout: 2))

        app.buttons["ResultsModeGridButton"].click()
        XCTAssertTrue(app.collectionViews["ResultsGrid"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testFilterFieldNarrowsVisibleResults() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--fixture-results"]
        app.launch()

        app.buttons["ResultsModeTableButton"].click()

        let filter = app.searchFields["ResultsFilterField"]
        filter.click()
        filter.typeText("report")

        XCTAssertTrue(app.staticTexts["report.txt"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["archive.txt"].exists)
    }
}
