import AppKit
import Testing
@testable import FileHound

struct MainMenuBuilderTests {
    @MainActor
    @Test
    func buildAddsEditMenuWithTextCommands() {
        let menu = MainMenuBuilder().build()

        #expect(menu.items.count == 4)

        let editMenu = try! #require(menu.item(at: 1)?.submenu)
        #expect(editMenu.items.contains { $0.action == #selector(NSText.copy(_:)) })
        #expect(editMenu.items.contains { $0.action == #selector(NSText.paste(_:)) })
        #expect(editMenu.items.contains { $0.action == #selector(NSText.selectAll(_:)) })

        let fileMenu = try! #require(menu.item(at: 2)?.submenu)
        #expect(fileMenu.items.contains { $0.action == #selector(NSWindow.performClose(_:)) })
    }

    @MainActor
    @Test
    func buildAddsRecentSearchSubmenuWhenEnabled() throws {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        let historyStore = SearchHistoryStore(storage: storage)
        try historyStore.record(
            RecentSearchRecord(
                title: "Name contains report",
                criteria: SearchCriteriaSnapshot(
                    scope: SearchScopeSnapshot(
                        title: "inside Downloads",
                        representedPath: "/Users/test/Downloads",
                        scopeDescription: "Downloads",
                        sourceKind: .folder
                    ),
                    rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
                )
            )
        )

        let menu = MainMenuBuilder(settings: settings, searchHistoryStore: historyStore).build()
        let appMenu = try #require(menu.item(at: 0)?.submenu)
        let recentItem = try #require(appMenu.items.first { $0.title == "Open Recent Search" })
        let recentMenu = try #require(recentItem.submenu)

        #expect(recentMenu.items.map(\.title) == ["Name contains report"])
    }

    @MainActor
    @Test
    func buildAddsSavedSearchSubmenuAndDisablesLegacyEntries() throws {
        let storage = InMemoryKeyValueStore()
        let savedSearchStore = SavedSearchStore(storage: storage)
        try storage.setCodable([
            LegacySavedSearchMenuFixture(
                name: "旧搜索",
                querySummary: "/tmp",
                createdAt: Date(timeIntervalSince1970: 123)
            )
        ], forKey: "savedSearches")

        let menu = MainMenuBuilder(
            settings: AppSettings(storage: storage),
            searchHistoryStore: SearchHistoryStore(storage: storage),
            savedSearchStore: savedSearchStore
        ).build()
        let appMenu = try #require(menu.item(at: 0)?.submenu)
        let savedItem = try #require(appMenu.items.first { $0.title == "Open Saved Search" })
        let savedMenu = try #require(savedItem.submenu)

        #expect(savedMenu.items.map(\.title) == ["旧搜索 (Summary Only)"])
        #expect(savedMenu.items.first?.isEnabled == false)
    }

    @MainActor
    @Test
    func buildAddsSavedSearchSubmenuForRestorableSearches() throws {
        let storage = InMemoryKeyValueStore()
        let criteria = SearchCriteriaSnapshot(
            scope: SearchScopeSnapshot(
                title: "inside Downloads",
                representedPath: "/Users/test/Downloads",
                scopeDescription: "Downloads",
                sourceKind: .folder
            ),
            rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
        )
        let savedSearchStore = SavedSearchStore(storage: storage)
        try savedSearchStore.save(name: "报告搜索", criteria: criteria, presentationState: ResultPresentationState(mode: .table))

        let menu = MainMenuBuilder(
            settings: AppSettings(storage: storage),
            searchHistoryStore: SearchHistoryStore(storage: storage),
            savedSearchStore: savedSearchStore
        ).build()
        let appMenu = try #require(menu.item(at: 0)?.submenu)
        let savedItem = try #require(appMenu.items.first { $0.title == "Open Saved Search" })
        let savedMenu = try #require(savedItem.submenu)

        #expect(savedMenu.items.map(\.title) == ["报告搜索"])
        #expect(savedMenu.items.first?.isEnabled == true)
    }

    @MainActor
    @Test
    func fileMenuIncludesSaveSearchCommand() {
        let menu = MainMenuBuilder().build()
        let fileMenu = try! #require(menu.item(at: 2)?.submenu)

        #expect(fileMenu.items.contains { $0.title == "Save Search…" })
    }

    @MainActor
    @Test
    func omitsRecentSearchSubmenuWhenDisabled() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.openRecentSearchMenu = false

        let menu = MainMenuBuilder(settings: settings, searchHistoryStore: SearchHistoryStore(storage: storage)).build()
        let appMenu = try! #require(menu.item(at: 0)?.submenu)

        #expect(appMenu.items.contains { $0.title == "Open Recent Search" } == false)
    }

    @MainActor
    @Test
    func appMenuIncludesCheckForUpdatesCommand() throws {
        let menu = MainMenuBuilder().build()
        let appMenu = try #require(menu.item(at: 0)?.submenu)
        let expectedTitle = L10n.string("menu.check_for_updates")
        let expectedAction = #selector(AppDelegate.checkForUpdates(_:))

        #expect(appMenu.items.contains { item in
            item.title == expectedTitle && item.action == expectedAction
        })
    }
}

private struct LegacySavedSearchMenuFixture: Codable {
    let name: String
    let querySummary: String
    let createdAt: Date
}
