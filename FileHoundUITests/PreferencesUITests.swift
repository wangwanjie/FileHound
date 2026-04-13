import XCTest

final class PreferencesUITests: XCTestCase {
    @MainActor
    func testPreferencesShowsSegmentedTabsAndAppearanceControls() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = ["--uitesting", "--open-preferences-on-launch"]
        app.launch()

        let window = app.windows["偏好设置"]
        XCTAssertTrue(window.waitForExistence(timeout: 3))
        XCTAssertTrue(window.popUpButtons["ThemePopup"].exists)
        XCTAssertTrue(window.popUpButtons["LanguagePopup"].exists)
        XCTAssertTrue(window.textFields["ResultsFontSizeField"].exists)
        XCTAssertTrue(window.buttons["DimColorButton"].exists)
    }

    func testSearchPreferencePersistsAcrossRelaunch() throws {
        let firstLaunch = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(firstLaunch)
        firstLaunch.launchArguments = [
            "--uitesting",
            "--open-preferences-on-launch",
            "--open-search-preferences-on-launch",
            "--disable-show-results-early"
        ]
        firstLaunch.launch()

        let firstCheckbox = firstLaunch.checkBoxes["SearchPreferenceShowResultsEarlyButton"]
        XCTAssertTrue(firstCheckbox.waitForExistence(timeout: 3))
        if checkboxValue(firstCheckbox) == "0" {
            firstCheckbox.click()
        }
        XCTAssertEqual(checkboxValue(firstCheckbox), "1")
        firstLaunch.terminate()

        let secondLaunch = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(secondLaunch)
        secondLaunch.launchArguments = [
            "--uitesting",
            "--open-preferences-on-launch",
            "--open-search-preferences-on-launch"
        ]
        secondLaunch.launch()

        let secondCheckbox = secondLaunch.checkBoxes["SearchPreferenceShowResultsEarlyButton"]
        XCTAssertTrue(secondCheckbox.waitForExistence(timeout: 3))
        XCTAssertEqual(checkboxValue(secondCheckbox), "1")
    }

    @MainActor
    func testSpecialFoldersWindowShowsListControls() throws {
        let app = XCUIApplication()
        AppLaunchHelper.prepareForLaunch(app)
        app.launchArguments = [
            "--uitesting",
            "--open-preferences-on-launch",
            "--open-search-preferences-on-launch"
        ]
        app.launch()

        let preferencesWindow = app.windows["偏好设置"]
        XCTAssertTrue(preferencesWindow.waitForExistence(timeout: 3))

        let triggerButton = preferencesWindow.buttons["SearchPreferenceSpecialFoldersButton"]
        XCTAssertTrue(triggerButton.waitForExistence(timeout: 2))
        triggerButton.click()

        let specialFoldersWindow = app.windows["特殊文件夹"]
        XCTAssertTrue(specialFoldersWindow.waitForExistence(timeout: 3))
        XCTAssertTrue(specialFoldersWindow.buttons["SpecialFoldersAddButton"].waitForExistence(timeout: 2))
        XCTAssertTrue(specialFoldersWindow.buttons["SpecialFoldersRemoveButton"].exists)
        XCTAssertTrue(specialFoldersWindow.tables["SpecialFoldersTable"].exists)
    }

    private func checkboxValue(_ checkbox: XCUIElement) -> String {
        String(describing: checkbox.value ?? "")
    }
}
