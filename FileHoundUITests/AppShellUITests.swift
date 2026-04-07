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

        XCTAssertTrue(app.windows["FileHound"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.splitGroups.firstMatch.exists)
        XCTAssertTrue(app.menuBars.menuBarItems["FileHound"].exists)
    }
}
