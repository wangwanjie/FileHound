import Foundation
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

        // 使用非默认值（默认为 onLaunch / 13），断言才有意义
        settings.updateCheckPolicy = .dailyAutomatic
        settings.resultsFontSize = 15

        #expect(settings.updateCheckPolicy == .dailyAutomatic)
        #expect(settings.resultsFontSize == 15)
        #expect(settings.updatesPreferences.updateCheckPolicy == .dailyAutomatic)
        #expect(settings.appearancePreferences.resultsFontSize == 15)

        // 新实例从同一存储读取，验证确实持久化
        let reloaded = AppSettings(storage: store)
        #expect(reloaded.updateCheckPolicy == .dailyAutomatic)
        #expect(reloaded.resultsFontSize == 15)
    }

    @Test
    func bridgesGeneralAndSearchPreferencesThroughLegacyKeys() {
        let store = InMemoryKeyValueStore()
        let settings = AppSettings(storage: store)

        settings.openRecentSearchMenu = false
        settings.restorePreviousSearch = true
        settings.tieResultsWindowToFindWindow = false
        // showResultsEarly 默认为 true，这里设为非默认值
        settings.showResultsEarly = false
        settings.includeSpotlightResults = false

        #expect(settings.generalPreferences.openRecentSearchMenu == false)
        #expect(settings.generalPreferences.restorePreviousSearch == true)
        #expect(settings.generalPreferences.tieResultsWindowToFindWindow == false)
        #expect(settings.searchExecutionPreferences.showResultsEarly == false)
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
            showResultsEarly: false,
            includeSpotlightResults: false
        )

        #expect(settings.launchShortcut == "cmd-shift-space")
        #expect(settings.activationMode == .finderOnly)
        #expect(settings.openRecentSearchMenu == false)
        #expect(settings.restorePreviousSearch == true)
        #expect(settings.tieResultsWindowToFindWindow == false)
        #expect(settings.quitWhenAllWindowsAreClosed == false)
        #expect(settings.expandFoldersWhenShowingResults == true)
        #expect(settings.showResultsEarly == false)
        #expect(settings.includeSpotlightResults == false)
    }

    @Test
    func corruptedGroupedBlobsFallBackToIndividualKeys() {
        let store = InMemoryKeyValueStore()
        let settings = AppSettings(storage: store)
        settings.restorePreviousSearch = true
        settings.showResultsEarly = false
        settings.resultsFontSize = 15
        settings.autoDownloadUpdates = true

        // v1 分组 blob 损坏时，逐项键仍是可信来源
        let garbage = Data("not json".utf8)
        store.set(garbage, forKey: "generalPreferences.v1")
        store.set(garbage, forKey: "searchExecutionPreferences.v1")
        store.set(garbage, forKey: "appearancePreferences.v1")
        store.set(garbage, forKey: "updatePreferences.v1")

        #expect(settings.generalPreferences.restorePreviousSearch == true)
        #expect(settings.searchExecutionPreferences.showResultsEarly == false)
        #expect(settings.appearancePreferences.resultsFontSize == 15)
        #expect(settings.updatesPreferences.autoDownloadUpdates == true)
    }
}
