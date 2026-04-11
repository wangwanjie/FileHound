//
//  AppShellUITests.swift
//  FileHoundUITests
//
//  Created by VanJay on 2026/4/8.
//

import XCTest

final class AppShellUITests: XCTestCase {
    @MainActor
    func testLaunchShowsModernSearchWorkspace() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting"]
        app.launch()

        XCTAssertTrue(app.windows["FileHound"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.popUpButtons["SearchScopePopup"].exists)
        XCTAssertTrue(app.popUpButtons["SearchRuleFieldPopup"].exists)
        XCTAssertTrue(app.textFields["SearchRuleValueField"].exists)
        XCTAssertTrue(app.buttons["PrimarySearchButton"].exists)
        XCTAssertTrue(app.staticTexts["SearchStatusLabel"].exists)
    }

    @MainActor
    func testSearchButtonSwitchesToStopDuringFixtureSearch() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting", "--fixture-delayed-search"]
        app.launch()

        let button = app.buttons["PrimarySearchButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()

        XCTAssertEqual(button.label, "Stop")
        XCTAssertTrue(app.activityIndicators["SearchActivityIndicator"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["SearchStatusLabel"].label.contains("Searching: Macintosh HD"))
    }
}
