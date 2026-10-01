import AppKit
import Testing
@testable import FileHound

struct MainMenuBuilderTests {
    @MainActor
    @Test
    func buildAddsEditMenuWithTextCommands() {
        let menu = MainMenuBuilder().build()

        #expect(menu.items.count == 6)

        let editMenu = try! #require(menu.item(at: 2)?.submenu)
        #expect(editMenu.items.contains { $0.action == #selector(NSText.copy(_:)) })
        #expect(editMenu.items.contains { $0.action == #selector(NSText.paste(_:)) })
        #expect(editMenu.items.contains { $0.action == #selector(NSText.selectAll(_:)) })

        let fileMenu = try! #require(menu.item(at: 1)?.submenu)
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
        let fileMenu = try #require(menu.item(at: 1)?.submenu)
        let recentItem = try #require(fileMenu.items.first { $0.title == L10n.string("menu.open_recent_search") })
        let recentMenu = try #require(recentItem.submenu)

        #expect(recentMenu.items.map(\.title) == ["Name contains report", "", L10n.string("menu.clear_recent_searches")])
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
        let fileMenu = try #require(menu.item(at: 1)?.submenu)
        let savedItem = try #require(fileMenu.items.first { $0.title == L10n.string("menu.open_saved_search") })
        let savedMenu = try #require(savedItem.submenu)

        #expect(savedMenu.items.map(\.title) == [L10n.format("menu.saved_search_summary_only", "旧搜索")])
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
        let fileMenu = try #require(menu.item(at: 1)?.submenu)
        let savedItem = try #require(fileMenu.items.first { $0.title == L10n.string("menu.open_saved_search") })
        let savedMenu = try #require(savedItem.submenu)

        #expect(savedMenu.items.map(\.title) == ["报告搜索"])
        #expect(savedMenu.items.first?.isEnabled == true)
    }

    @MainActor
    @Test
    func fileMenuIncludesSaveSearchCommand() throws {
        let menu = MainMenuBuilder().build()
        let fileMenu = try #require(menu.item(at: 1)?.submenu)

        #expect(fileMenu.items.contains { $0.title == L10n.string("menu.save_search") })
        let trashItem = try #require(fileMenu.items.first { $0.action == #selector(SearchResultsViewController.moveSelectedResultsToTrash(_:)) })
        #expect(trashItem.keyEquivalent == "\u{8}")
        #expect(trashItem.keyEquivalentModifierMask == [.command])
        #expect(fileMenu.items.contains { $0.action == #selector(SearchResultsViewController.openSelectedResults(_:)) && $0.keyEquivalent == "o" })
    }

    @MainActor
    @Test
    func fileMenuIncludesSearchAgainShortcut() throws {
        let menu = MainMenuBuilder().build()
        let fileMenu = try #require(menu.item(at: 1)?.submenu)
        let item = try #require(fileMenu.items.first { $0.action == #selector(SearchResultsWindowController.refreshSearchResults(_:)) })

        #expect(item.keyEquivalent == "r")
        #expect(item.target == nil)
    }

    @MainActor
    @Test
    func omitsRecentSearchSubmenuWhenDisabled() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.openRecentSearchMenu = false

        let menu = MainMenuBuilder(settings: settings, searchHistoryStore: SearchHistoryStore(storage: storage)).build()
        let fileMenu = try! #require(menu.item(at: 1)?.submenu)

        #expect(fileMenu.items.contains { $0.title == L10n.string("menu.open_recent_search") } == false)
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

extension MainMenuBuilderTests {
    @MainActor
    @Test
    func menuBarFollowsStandardOrderAndIncludesAppCommands() throws {
        let menu = MainMenuBuilder().build()
        let appMenu = try #require(menu.item(at: 0)?.submenu)
        let fileMenu = try #require(menu.item(at: 1)?.submenu)
        let viewMenu = try #require(menu.item(at: 3)?.submenu)

        #expect(menu.items.map(\.title) == [
            "FileHound",
            L10n.string("menu.file"),
            L10n.string("menu.edit"),
            L10n.string("menu.view"),
            L10n.string("menu.window"),
            L10n.string("menu.help")
        ])
        #expect(appMenu.items.contains { $0.action == #selector(NSApplication.hide(_:)) && $0.keyEquivalent == "h" })
        #expect(appMenu.items.contains { $0.action == #selector(NSApplication.hideOtherApplications(_:)) })
        #expect(appMenu.items.contains { $0.title == L10n.string("menu.services") && $0.submenu != nil })

        let newSearch = try #require(fileMenu.items.first { $0.action == #selector(AppDelegate.presentSearchWindow(_:)) })
        #expect(newSearch.keyEquivalent == "n")
        #expect(viewMenu.items.map(\.keyEquivalent) == ["1", "2", "3"])
    }

    @MainActor
    @Test
    func recentSearchMenuRefreshesAndClears() throws {
        let storage = InMemoryKeyValueStore()
        let historyStore = SearchHistoryStore(storage: storage)
        let builder = MainMenuBuilder(settings: AppSettings(storage: storage), searchHistoryStore: historyStore)
        let menu = builder.build()
        let fileMenu = try #require(menu.item(at: 1)?.submenu)
        let recentMenu = try #require(fileMenu.items.first { $0.title == L10n.string("menu.open_recent_search") }?.submenu)
        #expect(recentMenu.items.map(\.title) == [L10n.string("menu.no_recent_searches")])

        let criteria = SearchCriteriaSnapshot(
            scope: SearchScopeSnapshot(title: "Home", representedPath: "/tmp", scopeDescription: "Home", sourceKind: .folder),
            rules: [SearchRuleSelection(field: .name, operator: .contains, value: "a")]
        )
        try historyStore.record(RecentSearchRecord(title: "first", criteria: criteria))
        try historyStore.record(RecentSearchRecord(title: "again", criteria: criteria))
        builder.menuNeedsUpdate(recentMenu)
        #expect(recentMenu.items.first?.title == "again")
        #expect(recentMenu.items.count == 3)

        builder.clearRecentSearches(nil)
        #expect(historyStore.all().isEmpty)
        #expect(recentMenu.items.map(\.title) == [L10n.string("menu.no_recent_searches")])
    }
}

private struct LegacySavedSearchMenuFixture: Codable {
    let name: String
    let querySummary: String
    let createdAt: Date
}
