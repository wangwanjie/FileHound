import XCTest

final class SearchWindowUITests: XCTestCase {
    @MainActor
    func testAddingRulesKeepsWindowTopAnchoredAndEventuallyCapsHeight() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting"]
        app.launch()

        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 3))

        let addButton = app.buttons["SearchRuleAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 2))

        let initialFrame = window.frame
        addButton.click()
        waitBriefly()

        let expandedFrame = window.frame
        XCTAssertGreaterThan(expandedFrame.height, initialFrame.height)
        XCTAssertEqual(expandedFrame.width, initialFrame.width, accuracy: 1)
        XCTAssertEqual(expandedFrame.minY, initialFrame.minY, accuracy: 3)

        let scrollView = app.scrollViews["SearchRulesScrollView"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 2))

        var lastFrame = expandedFrame
        for _ in 0..<20 {
            app.buttons["SearchRuleAddButton"].firstMatch.click()
            waitBriefly()
            lastFrame = window.frame
            if String(describing: scrollView.value ?? "") == "scrolling" {
                break
            }
        }
        XCTAssertEqual(String(describing: scrollView.value ?? ""), "scrolling")

        let cappedFrame = lastFrame
        app.buttons["SearchRuleAddButton"].firstMatch.click()
        waitBriefly()
        let cappedAgainFrame = window.frame
        XCTAssertEqual(cappedAgainFrame.height, cappedFrame.height, accuracy: 2)
        XCTAssertEqual(cappedAgainFrame.width, initialFrame.width, accuracy: 1)
    }

    @MainActor
    func testRuleValueFieldAcceptsTyping() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting"]
        app.launch()

        let valueField = app.textFields["SearchRuleValueField"]
        XCTAssertTrue(valueField.waitForExistence(timeout: 3))

        valueField.click()
        valueField.typeKey("a", modifierFlags: .command)
        valueField.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        valueField.typeText("report")

        XCTAssertEqual(valueField.value as? String, "report")
    }

    @MainActor
    func testStopReturnsToEditableStateWithLatestMatchCount() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting", "--fixture-streaming-search-slow", "--disable-show-results-early"]
        app.launch()

        let primaryButton = app.buttons["PrimarySearchButton"]
        let statusLabel = app.staticTexts["SearchStatusLabel"]
        let scopePopup = app.popUpButtons["SearchScopePopup"]

        XCTAssertTrue(primaryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 3))
        primaryButton.click()

        XCTAssertTrue(waitUntil(timeout: 2) { primaryButton.label == "Stop" })
        XCTAssertTrue(waitUntil(timeout: 2) { statusLabel.label.contains("1 matched") })

        primaryButton.click()

        XCTAssertTrue(waitUntil(timeout: 2) { primaryButton.label == "Find" })
        XCTAssertTrue(waitUntil(timeout: 2) { statusLabel.label.contains("Items Found: 1") })
        XCTAssertTrue(waitUntil(timeout: 2) { scopePopup.isEnabled })
    }

    private func waitBriefly() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
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
