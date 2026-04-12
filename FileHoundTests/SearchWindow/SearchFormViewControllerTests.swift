import AppKit
import Testing
@testable import FileHound

struct SearchFormViewControllerTests {
    @MainActor
    @Test
    func primaryActionEntersSearchingStateImmediately() {
        let controller = SearchFormViewController()
        _ = controller.view

        controller.debugTriggerPrimaryAction()

        #expect(controller.debugPrimaryActionTitle == L10n.string("search_window.action.stop"))
        #expect(controller.debugStatusText == L10n.format("search_window.status.searching", "Macintosh HD", 0))
    }

    @MainActor
    @Test
    func loadsRecentLocationsIntoScopePopup() throws {
        let storage = InMemoryKeyValueStore()
        let recentLocationStore = RecentLocationStore(storage: storage)
        try recentLocationStore.remember(
            scope: SearchScopeSnapshot(
                title: "inside Downloads",
                representedPath: "/Users/test/Downloads",
                scopeDescription: "Downloads",
                sourceKind: .folder
            )
        )

        let controller = SearchFormViewController(recentLocationStore: recentLocationStore)
        _ = controller.view

        #expect(controller.debugScopeTitles.contains { $0.contains("Downloads") })
    }

    @MainActor
    @Test
    func loadsDuplicateMountedVolumeScopesWithoutCrashing() throws {
        let storage = InMemoryKeyValueStore()
        let recentLocationStore = RecentLocationStore(storage: storage)
        try recentLocationStore.remember(
            scope: SearchScopeSnapshot(
                title: "on webdav.stun.vanjay.cn",
                representedPath: "/Volumes/webdav.stun.vanjay.cn",
                scopeDescription: "webdav.stun.vanjay.cn",
                sourceKind: .mountedVolume
            )
        )

        let controller = SearchFormViewController(
            scopeProvider: SearchScopeMenuProvider(mountedVolumes: ["webdav.stun.vanjay.cn"]),
            recentLocationStore: recentLocationStore,
            searchHistoryStore: SearchHistoryStore(storage: storage),
            searchSessionStore: SearchSessionStore(storage: storage),
            settings: AppSettings(storage: storage)
        )
        _ = controller.view

        #expect(controller.debugScopeTitles.filter { $0.contains("webdav.stun.vanjay.cn") }.count == 1)
    }

    @MainActor
    @Test
    func restoresPreviousSearchWhenEnabled() throws {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.restorePreviousSearch = true
        let sessionStore = SearchSessionStore(storage: storage)
        let snapshot = SearchSessionSnapshot(
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
        try sessionStore.save(snapshot)

        let controller = SearchFormViewController(
            recentLocationStore: RecentLocationStore(storage: storage),
            searchHistoryStore: SearchHistoryStore(storage: storage),
            searchSessionStore: sessionStore,
            settings: settings
        )
        _ = controller.view

        #expect(controller.debugSelectedScopeTitle?.contains("Downloads") == true)
        #expect(controller.debugCurrentSelections == [SearchRuleSelection(field: .name, operator: .contains, value: "report")])
    }

    @MainActor
    @Test
    func reusesResultsWindowWhenTiePreferenceIsEnabled() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.tieResultsWindowToFindWindow = true

        let controller = SearchFormViewController(settings: settings)
        _ = controller.view

        controller.debugOpenResultsWindow(title: "First")
        let firstIdentifier = try! #require(controller.debugResultsWindowIdentifier)

        controller.debugOpenResultsWindow(
            title: "Second",
            items: [SearchResultItem(path: "/tmp/second.txt", matchReason: "名称命中", previewSnippet: nil)]
        )

        #expect(controller.debugResultsWindowIdentifier == firstIdentifier)
    }

    @MainActor
    @Test
    func createsNewResultsWindowWhenTiePreferenceIsDisabled() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.tieResultsWindowToFindWindow = false

        let controller = SearchFormViewController(settings: settings)
        _ = controller.view

        controller.debugOpenResultsWindow(title: "First")
        let firstIdentifier = try! #require(controller.debugResultsWindowIdentifier)

        controller.debugOpenResultsWindow(
            title: "Second",
            items: [SearchResultItem(path: "/tmp/second.txt", matchReason: "名称命中", previewSnippet: nil)]
        )

        #expect(controller.debugResultsWindowIdentifier != firstIdentifier)
    }

    @MainActor
    @Test
    func reappliesSavedPresentationStateWhenOpeningResultsFromRestoredSearch() {
        let presentationState = ResultPresentationState(
            mode: .table,
            sortField: .path,
            sortOrder: .descending,
            filterText: "report",
            showInvisibleItems: true,
            showPackageContents: true,
            showTrashedItems: true,
            previewSize: 96
        )
        let controller = SearchFormViewController()
        _ = controller.view

        controller.applySearchSessionSnapshot(
            SearchSessionSnapshot(
                criteria: SearchCriteriaSnapshot(
                    scope: SearchScopeSnapshot(
                        title: "inside Downloads",
                        representedPath: "/Users/test/Downloads",
                        scopeDescription: "Downloads",
                        sourceKind: .folder
                    ),
                    rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
                ),
                presentationState: presentationState
            )
        )
        controller.debugOpenResultsWindow()

        #expect(controller.debugResultsPresentationState == presentationState)
    }

    @MainActor
    @Test
    func restoredSearchAppliesSavedPresentationStateWhenReusingTiedResultsWindow() {
        let presentationState = ResultPresentationState(
            mode: .table,
            sortField: .path,
            sortOrder: .descending,
            filterText: "report",
            showInvisibleItems: true,
            previewSize: 88
        )
        let controller = SearchFormViewController()
        _ = controller.view

        controller.debugOpenResultsWindow()
        let firstIdentifier = try! #require(controller.debugResultsWindowIdentifier)

        controller.applySearchSessionSnapshot(
            SearchSessionSnapshot(
                criteria: SearchCriteriaSnapshot(
                    scope: SearchScopeSnapshot(
                        title: "inside Downloads",
                        representedPath: "/Users/test/Downloads",
                        scopeDescription: "Downloads",
                        sourceKind: .folder
                    ),
                    rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
                ),
                presentationState: presentationState
            )
        )
        controller.debugOpenResultsWindow(
            title: "Restored",
            items: [SearchResultItem(path: "/tmp/restored.txt", matchReason: "名称命中", previewSnippet: nil)]
        )

        #expect(controller.debugResultsWindowIdentifier == firstIdentifier)
        #expect(controller.debugResultsPresentationState == presentationState)
    }

    @MainActor
    @Test
    func invalidRulesDisableFindAndKeepEditingState() {
        let controller = SearchFormViewController()
        _ = controller.view

        controller.applySearchSessionSnapshot(
            SearchSessionSnapshot(
                criteria: SearchCriteriaSnapshot(
                    scope: controller.debugCurrentSearchSessionSnapshot.criteria.scope,
                    rules: [SearchRuleSelection(field: .kind, operator: .isNot, value: "kind.any")]
                )
            )
        )

        #expect(controller.debugPrimaryActionEnabled == false)
        #expect(controller.debugStatusText == L10n.string("search_rule.validation.kind_not_any"))

        controller.debugTriggerPrimaryAction()

        #expect(controller.debugPrimaryActionTitle == L10n.string("search_window.action.find"))
    }
}
