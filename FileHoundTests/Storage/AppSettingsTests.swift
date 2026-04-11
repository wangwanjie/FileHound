import Testing
@testable import FileHound

struct AppSettingsTests {
    @Test
    func defaultsShowResultsEarlyForFreshInstall() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())

        #expect(settings.showResultsEarly == true)
        #expect(settings.searchExecutionPreferences.showResultsEarly == true)
    }

    @Test
    func persistsUpdatePolicyAndFontSize() {
        let store = InMemoryKeyValueStore()
        let settings = AppSettings(storage: store)

        settings.updateCheckPolicy = .dailyAutomatic
        settings.resultsFontSize = 13

        #expect(settings.updateCheckPolicy == .dailyAutomatic)
        #expect(settings.resultsFontSize == 13)
        #expect(settings.updatesPreferences.updateCheckPolicy == .dailyAutomatic)
        #expect(settings.appearancePreferences.resultsFontSize == 13)
    }

    @Test
    func bridgesGeneralAndSearchPreferencesThroughLegacyKeys() {
        let store = InMemoryKeyValueStore()
        let settings = AppSettings(storage: store)

        settings.openRecentSearchMenu = false
        settings.restorePreviousSearch = true
        settings.tieResultsWindowToFindWindow = false
        settings.showResultsEarly = true
        settings.includeSpotlightResults = false

        #expect(settings.generalPreferences.openRecentSearchMenu == false)
        #expect(settings.generalPreferences.restorePreviousSearch == true)
        #expect(settings.generalPreferences.tieResultsWindowToFindWindow == false)
        #expect(settings.searchExecutionPreferences.showResultsEarly == true)
        #expect(settings.searchExecutionPreferences.includeSpotlightResults == false)
    }

    @Test
    func persistsGroupedPreferencesBackToPrimitiveAccessors() {
        let store = InMemoryKeyValueStore()
        let settings = AppSettings(storage: store)

        settings.generalPreferences = GeneralSearchPreferences(
            launchShortcut: "cmd-shift-space",
            activationMode: .finderOnly,
            openRecentSearchMenu: false,
            restorePreviousSearch: true,
            tieResultsWindowToFindWindow: false,
            quitWhenAllWindowsAreClosed: false
        )
        settings.searchExecutionPreferences = SearchExecutionPreferences(
            expandFoldersWhenShowingResults: true,
            showResultsEarly: true,
            includeSpotlightResults: false
        )

        #expect(settings.launchShortcut == "cmd-shift-space")
        #expect(settings.activationMode == .finderOnly)
        #expect(settings.openRecentSearchMenu == false)
        #expect(settings.restorePreviousSearch == true)
        #expect(settings.tieResultsWindowToFindWindow == false)
        #expect(settings.quitWhenAllWindowsAreClosed == false)
        #expect(settings.expandFoldersWhenShowingResults == true)
        #expect(settings.showResultsEarly == true)
        #expect(settings.includeSpotlightResults == false)
    }
}
