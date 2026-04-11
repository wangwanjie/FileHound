import AppKit
import Testing
@testable import FileHound

struct PreferencesWindowControllerTests {
    @MainActor
    @Test
    func createsCompactNonResizableWindow() {
        let controller = PreferencesWindowController()
        let window = try! #require(controller.window)

        #expect(window.styleMask.contains(.resizable) == false)
        #expect(window.contentLayoutRect.width < 700)
        #expect(window.contentLayoutRect.height < 500)
    }

    @MainActor
    @Test
    func activeSectionUsesRoundedCardBackground() {
        let controller = PreferencesWindowController()
        controller.show()

        let rootController = try! #require(controller.window?.contentViewController as? PreferencesRootViewController)
        #expect(rootController.debugActiveSectionHasCardBackground == true)
    }
}

struct AppearancePreferencesViewControllerTests {
    @MainActor
    @Test
    func appearanceSelectionsUpdateThemeAndLanguageControllers() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        let themeController = ThemeController(settings: settings)
        let localizationController = LocalizationController(settings: settings)
        let controller = AppearancePreferencesViewController(
            settings: settings,
            themeController: themeController,
            localizationController: localizationController
        )
        _ = controller.view

        controller.debugSelectTheme(.dark)
        controller.debugSelectLanguage(.en)

        #expect(settings.preferredTheme == .dark)
        #expect(themeController.currentTheme == .dark)
        #expect(settings.preferredLanguage == .en)
        #expect(localizationController.currentLanguage == .en)
    }

    @MainActor
    @Test
    func appearanceResetReturnsSettingsToDefaults() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.preferredTheme = .dark
        settings.preferredLanguage = .en
        settings.resultsFontSize = 18
        settings.dimColorHex = "#6E7E91"
        let controller = AppearancePreferencesViewController(
            settings: settings,
            themeController: ThemeController(settings: settings),
            localizationController: LocalizationController(settings: settings)
        )
        _ = controller.view

        controller.debugTriggerResetDefaults()

        #expect(settings.preferredTheme == .system)
        #expect(settings.preferredLanguage == .system)
        #expect(settings.resultsFontSize == 13)
        #expect(settings.dimColorHex == "#A0A7B3")
        #expect(controller.debugSelectedTheme == .system)
        #expect(controller.debugSelectedLanguage == .system)
        #expect(controller.debugFontSizeValue == 13)
        #expect(controller.debugDimColorHex == "#A0A7B3")
    }
}

struct UpdatePreferencesViewControllerTests {
    @MainActor
    @Test
    func updateResetReturnsSettingsToDefaults() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.updateCheckPolicy = .dailyAutomatic
        settings.autoDownloadUpdates = true
        let controller = UpdatePreferencesViewController(settings: settings)
        _ = controller.view

        controller.debugTriggerResetDefaults()

        #expect(settings.updateCheckPolicy == .onLaunch)
        #expect(settings.autoDownloadUpdates == false)
        #expect(controller.debugSelectedPolicyIndex == 0)
        #expect(controller.debugAutoDownloadEnabled == false)
    }
}

struct SpecialFoldersEditorViewControllerTests {
    @MainActor
    @Test
    func specialFoldersEditorPersistsAddedUpdatedAndRemovedRules() throws {
        let storage = InMemoryKeyValueStore()
        let store = SpecialFoldersStore(storage: storage)
        let controller = SpecialFoldersEditorViewController(store: store)
        _ = controller.view

        controller.debugAddRule(path: "/Users/test/Library", disposition: .exclude)
        controller.debugAddRule(path: "/Users/test/Downloads", disposition: .slowSearch)
        controller.debugSetDisposition(.include, at: 0)
        controller.debugRemoveRule(at: 1)

        let rules = store.load().rules
        #expect(rules.count == 1)
        #expect(rules.first?.path == "/Users/test/Library")
        #expect(rules.first?.disposition == .include)
        #expect(controller.debugRules == rules)
    }
}
