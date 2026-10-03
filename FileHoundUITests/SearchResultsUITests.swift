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

        let statusLabel = app.staticTexts["SearchResultsStatusLabel"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 1))
        XCTAssertTrue(statusLabel.label.hasPrefix("Searching"))

        XCTAssertTrue(waitUntil(timeout: 3) { primaryButton.label == "Find" })
        XCTAssertTrue(waitUntil(timeout: 1) { statusLabel.label == "3 matched" })
    }

    @MainActor
    func testShowResultsButtonOpensPartialResultsAndKeepsUpdatingDuringSearch() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        // 断言依赖英文文案，固定界面语言避免受系统语言影响
        app.launchArguments = [
            "--uitesting",
            "--fixture-streaming-search-slow",
            "--disable-show-results-early",
            "-AppleLanguages", "(en)"
        ]
        app.launch()

        let primaryButton = app.buttons["PrimarySearchButton"]
        let showResultsButton = app.buttons["ShowLastResultsButton"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 3))

        // 不依赖上次会话恢复出的规则值，自行填入条件让「查找」可用
        let valueField = app.textFields["SearchRuleValueField"]
        XCTAssertTrue(valueField.waitForExistence(timeout: 3))
        valueField.click()
        valueField.typeKey("a", modifierFlags: .command)
        valueField.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        valueField.typeText("report")
        XCTAssertTrue(waitUntil(timeout: 2) { primaryButton.isEnabled })

        primaryButton.click()

        // 找到第一条结果后出现「Show Results」，此时结果窗口尚未打开
        XCTAssertTrue(waitUntil(timeout: 3) { showResultsButton.exists && showResultsButton.isHittable })
        XCTAssertEqual(showResultsButton.label, "Show Results")
        XCTAssertEqual(primaryButton.label, "Stop")
        XCTAssertEqual(app.windows.count, 1)

        showResultsButton.click()

        XCTAssertTrue(waitUntil(timeout: 1) { app.windows.count > 1 })
        XCTAssertTrue(app.staticTexts["report.txt"].waitForExistence(timeout: 1))
        XCTAssertFalse(showResultsButton.exists && showResultsButton.isHittable)
        let statusLabel = app.staticTexts["SearchResultsStatusLabel"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 1))
        XCTAssertTrue(statusLabel.label.hasPrefix("Searching"))

        // 剩余搜索继续把新条目刷新到已打开的结果页
        XCTAssertTrue(app.staticTexts["archive.txt"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntil(timeout: 4) { primaryButton.label == "Find" })
        XCTAssertTrue(waitUntil(timeout: 1) { statusLabel.label == "3 matched" })
        XCTAssertEqual(app.windows.count, 2)
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
