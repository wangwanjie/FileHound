import XCTest

final class SearchResultsUITests: XCTestCase {
    @MainActor
    func testSwitchesBetweenGridTableAndTreeModes() throws {
        let gridApp = launchFixtureResultsApp(extraArguments: ["--fixture-results-grid-mode"])
        XCTAssertTrue(gridApp.collectionViews["ResultsGrid"].waitForExistence(timeout: 3))
        gridApp.terminate()

        let tableApp = launchFixtureResultsApp(extraArguments: ["--fixture-results-table-mode"])
        XCTAssertTrue(tableApp.tables["ResultsTable"].waitForExistence(timeout: 3))
        tableApp.terminate()

        let treeApp = launchFixtureResultsApp(extraArguments: ["--fixture-results-tree-mode"])
        XCTAssertTrue(treeApp.outlines["ResultsOutline"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testFilterFieldNarrowsVisibleResults() throws {
        let app = launchFixtureResultsApp(extraArguments: [
            "--fixture-results-table-mode",
            "--fixture-results-filter-report"
        ])

        XCTAssertTrue(app.tables["ResultsTable"].waitForExistence(timeout: 3))

        let filter = app.searchFields["ResultsFilterField"]
        XCTAssertTrue(filter.waitForExistence(timeout: 2))

        XCTAssertTrue(app.staticTexts["report.txt"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["archive.txt"].exists)
    }

    @MainActor
    func testShowResultsEarlyOpensResultsWindowBeforeSearchCompletes() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting", "--fixture-streaming-search", "--enable-show-results-early"]
        app.launch()

        let primaryButton = app.buttons["PrimarySearchButton"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 3))

        primaryButton.click()

        XCTAssertTrue(waitUntil(timeout: 1.0) { app.windows.count > 1 })
        XCTAssertEqual(primaryButton.label, "Stop")
    }

    @MainActor
    func testTieResultsWindowReuseKeepsSingleResultsWindowAcrossRepeatedSearches() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = [
            "--uitesting",
            "--fixture-streaming-search",
            "--enable-show-results-early",
            "--enable-tie-results-window"
        ]
        app.launch()

        let primaryButton = app.buttons["PrimarySearchButton"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 3))

        primaryButton.click()
        XCTAssertTrue(waitUntil(timeout: 3) { primaryButton.label == "Find" && app.windows.count == 2 })

        primaryButton.click()
        XCTAssertTrue(waitUntil(timeout: 3) { primaryButton.label == "Find" && app.windows.count == 2 })
    }

    private func launchStreamingResultsApp() -> XCUIApplication {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting", "--fixture-streaming-search", "--enable-show-results-early"]
        app.launch()
        return app
    }

    private func launchFixtureResultsApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting", "--fixture-results"] + extraArguments
        app.launch()
        return app
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
