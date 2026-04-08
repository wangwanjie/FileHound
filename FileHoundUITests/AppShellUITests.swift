//
//  AppShellUITests.swift
//  FileHoundUITests
//
//  Created by VanJay on 2026/4/8.
//

import XCTest

final class AppShellUITests: XCTestCase {
    @MainActor
    func testLaunchShowsSearchWorkspace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        XCTAssertTrue(app.windows["Find Any File"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Find Items"].exists)
        XCTAssertTrue(app.menuBars.menuBarItems["FileHound"].exists)
    }
}
