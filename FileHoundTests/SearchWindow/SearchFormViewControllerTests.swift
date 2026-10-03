import AppKit
import Testing
@testable import FileHound

struct SearchFormViewControllerTests {
    @MainActor
    @Test
    func primaryActionEntersSearchingStateWhenRulesAreValid() {
        let controller = SearchFormViewController()
        _ = controller.view

        controller.applySearchSessionSnapshot(
            SearchSessionSnapshot(
                criteria: SearchCriteriaSnapshot(
                    scope: controller.debugCurrentSearchSessionSnapshot.criteria.scope,
                    rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
                )
            )
        )

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
    @Test(arguments: [true, false])
    func showLastResultsButtonReopensClosedResultsWindow(tieResultsWindow: Bool) throws {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.tieResultsWindowToFindWindow = tieResultsWindow

        let controller = SearchFormViewController(settings: settings)
        _ = controller.view
        #expect(controller.debugShowLastResultsButtonVisible == false)

        let title = "Last results \(UUID().uuidString)"
        controller.debugOpenResultsWindow(title: title)
        #expect(controller.debugShowLastResultsButtonVisible == false)

        let resultsWindow = try #require(NSApp.windows.first { $0.title == title })
        resultsWindow.close()
        #expect(controller.debugShowLastResultsButtonVisible)

        controller.debugShowLastResults()
        #expect(resultsWindow.isVisible)
        #expect(controller.debugShowLastResultsButtonVisible == false)
        resultsWindow.close()
    }

    @MainActor
    @Test
    func showResultsButtonRevealsPartialResultsAndKeepsUpdatingDuringSearch() throws {
        let workflowController = SearchWorkflowController()
        let controller = SearchFormViewController(
            workflowController: workflowController,
            settings: AppSettings(storage: InMemoryKeyValueStore())
        )
        controller.view.frame = NSRect(x: 0, y: 0, width: 720, height: 360)
        let title = "Name contains partial-reveal"
        let items = [
            SearchResultItem(path: "/tmp/report.txt", matchReason: "名称命中", previewSnippet: "report"),
            SearchResultItem(path: "/tmp/archive.txt", matchReason: "名称命中", previewSnippet: "archive")
        ]
        func deliver(_ count: Int) {
            workflowController.debugDeliverProgress(
                SearchExecutionProgress(title: title, items: Array(items.prefix(count)), matchedCount: count),
                scopeDescription: "Home",
                showResultsEarly: false
            )
        }
        func resultsWindows() -> [NSWindow] {
            NSApp.windows.filter { $0.title == title && $0.isVisible }
        }
        defer { resultsWindows().forEach { $0.close() } }

        // 未开启「提前显示搜索结果」：搜索中尚无匹配时不显示按钮
        workflowController.onStateChange?(.init(phase: .searching(scopeDescription: "Home", matchCount: 0)))
        #expect(controller.debugShowLastResultsButtonVisible == false)

        // 找到条目后出现「显示结果」，但结果窗口不会自动打开
        deliver(1)
        #expect(controller.debugShowLastResultsButtonVisible)
        #expect(controller.debugShowLastResultsButtonTitle == L10n.string("search_window.action.show_results"))
        #expect(resultsWindows().isEmpty)
        // 按钮必须完整显示标题，且夹在转圈指示器与主按钮之间、互不重叠
        let frames = controller.debugStatusBarFrames()
        #expect(frames.showResults.width >= frames.fittingWidth - 1)
        #expect(frames.showResults.width > 40)
        #expect(frames.showResults.maxX <= frames.primary.minX)
        #expect(frames.activity.maxX <= frames.showResults.minX)

        // 点击后立即展示已找到的结果，结果页处于搜索中状态，按钮隐藏
        controller.debugShowLastResults()
        let resultsWindow = try #require(resultsWindows().first)
        let resultsViewController = try #require(resultsWindow.contentViewController as? SearchResultsViewController)
        #expect(resultsViewController.debugShowsSearchActivity)
        #expect(resultsViewController.debugStatusText == L10n.format("results.status.searching", 1))
        #expect(controller.debugShowLastResultsButtonVisible == false)

        // 剩余搜索找到的新条目继续刷新同一个结果页
        deliver(2)
        #expect(resultsWindows().count == 1)
        #expect(resultsViewController.debugStatusText == L10n.format("results.status.searching", 2))

        // 搜索中关闭结果页后按钮重新出现，点击直接把同一窗口带回前台
        resultsWindow.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(controller.debugShowLastResultsButtonVisible)
        controller.debugShowLastResults()
        #expect(resultsWindow.isVisible)
        #expect(controller.debugShowLastResultsButtonVisible == false)

        workflowController.onStateChange?(.init(phase: .idle(matchCount: 2)))
        #expect(resultsViewController.debugShowsSearchActivity == false)
        #expect(controller.debugShowLastResultsButtonVisible == false)
    }

    @MainActor
    @Test
    func showResultsButtonStaysHiddenWhenResultsAlreadyShownEarly() {
        let workflowController = SearchWorkflowController()
        let controller = SearchFormViewController(
            workflowController: workflowController,
            settings: AppSettings(storage: InMemoryKeyValueStore())
        )
        _ = controller.view
        let title = "Name contains early-results"
        defer { NSApp.windows.filter { $0.title == title }.forEach { $0.close() } }

        workflowController.onStateChange?(.init(phase: .searching(scopeDescription: "Home", matchCount: 0)))
        workflowController.debugDeliverProgress(
            SearchExecutionProgress(
                title: title,
                items: [SearchResultItem(path: "/tmp/report.txt", matchReason: "名称命中", previewSnippet: "report")],
                matchedCount: 1
            ),
            scopeDescription: "Home",
            showResultsEarly: true
        )

        #expect(NSApp.windows.contains { $0.title == title && $0.isVisible })
        #expect(controller.debugShowLastResultsButtonVisible == false)
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

    @MainActor
    @Test
    func emptyRequiredRulesDisableFindAndKeepEditingState() {
        let controller = SearchFormViewController()
        _ = controller.view

        controller.applySearchSessionSnapshot(
            SearchSessionSnapshot(
                criteria: SearchCriteriaSnapshot(
                    scope: controller.debugCurrentSearchSessionSnapshot.criteria.scope,
                    rules: [SearchRuleSelection(field: .name, operator: .contains, value: "")]
                )
            )
        )

        #expect(controller.debugPrimaryActionEnabled == false)
        #expect(controller.debugStatusText == L10n.string("search_rule.validation.value_required"))

        controller.debugTriggerPrimaryAction()

        #expect(controller.debugPrimaryActionTitle == L10n.string("search_window.action.find"))
    }

    @MainActor
    @Test
    func fixingRequiredRuleValueReEnablesFindButtonImmediately() {
        let controller = SearchFormViewController()
        _ = controller.view

        controller.debugApplySelectionsThroughRulesEditor([
            SearchRuleSelection(field: .name, operator: .contains, value: "")
        ])
        #expect(controller.debugPrimaryActionEnabled == false)

        controller.debugApplySelectionsThroughRulesEditor([
            SearchRuleSelection(field: .name, operator: .contains, value: "report")
        ])

        #expect(controller.debugPrimaryActionEnabled == true)
        #expect(controller.debugStatusText == L10n.format("search_window.status.items_found", 0))
    }

    @MainActor
    @Test
    func windowBackgroundRefreshesAcrossAppearances() {
        let controller = SearchFormViewController()
        _ = controller.view

        let light = controller.debugRootBackgroundHex(for: .aqua)
        let dark = controller.debugRootBackgroundHex(for: .darkAqua)

        #expect(light != dark)
    }
}
