import AppKit
import Testing
@testable import FileHound

/// 查找窗口测试的封闭环境：设置与各存储都基于内存，卷宗列表为空，执行器不读真实的特殊文件夹配置，也不走 Spotlight
@MainActor
struct SearchFormTestEnvironment {
    let storage = InMemoryKeyValueStore()
    let settings: AppSettings
    let recentLocationStore: RecentLocationStore
    let searchHistoryStore: SearchHistoryStore
    let searchSessionStore: SearchSessionStore
    let workflowController: SearchWorkflowController

    init() {
        settings = AppSettings(storage: storage)
        settings.includeSpotlightResults = false
        settings.showResultsEarly = false
        recentLocationStore = RecentLocationStore(storage: storage)
        searchHistoryStore = SearchHistoryStore(storage: storage)
        searchSessionStore = SearchSessionStore(storage: storage)
        workflowController = SearchWorkflowController(
            executor: SearchExecutor(specialFoldersStore: SpecialFoldersStore(storage: storage))
        )
    }

    func makeFormController(
        mountedVolumes: [SearchScopeMountedVolume] = [],
        restoresPreviousSession: Bool = true
    ) -> SearchFormViewController {
        SearchFormViewController(
            workflowController: workflowController,
            scopeProvider: SearchScopeMenuProvider(mountedVolumes: { mountedVolumes }),
            scopeResolver: SearchScopeResolver(mountedVolumes: { [] }, finderSelection: { nil }),
            recentLocationStore: recentLocationStore,
            searchHistoryStore: searchHistoryStore,
            searchSessionStore: searchSessionStore,
            settings: settings,
            restoresPreviousSession: restoresPreviousSession
        )
    }

    func makeWindowController(restoresPreviousSession: Bool = true) -> SearchWindowController {
        SearchWindowController(formController: makeFormController(restoresPreviousSession: restoresPreviousSession))
    }

    /// 以临时目录为范围的会话快照
    static func folderSnapshot(_ url: URL, value: String = "report") -> SearchSessionSnapshot {
        SearchSessionSnapshot(
            criteria: SearchCriteriaSnapshot(
                scope: SearchScopeSnapshot(
                    title: "inside \(url.lastPathComponent)",
                    representedPath: url.path,
                    scopeDescription: url.lastPathComponent,
                    sourceKind: .folder
                ),
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: value)]
            )
        )
    }

    static func request(scopeDescription: String, rootPath: String, value: String) -> SearchRequest {
        SearchRequest(
            scopeDescription: scopeDescription,
            rootPath: rootPath,
            rules: [SearchRuleSelection(field: .name, operator: .contains, value: value)]
        )
    }
}

struct SearchFormViewControllerTests {
    private static let refreshMenuItem = NSMenuItem(
        title: "",
        action: #selector(SearchResultsWindowController.refreshSearchResults(_:)),
        keyEquivalent: ""
    )

    @MainActor
    private func closeWindows(titled titles: [String]) {
        NSApp.windows.filter { titles.contains($0.title) }.forEach { $0.close() }
    }

    @MainActor
    @Test
    func primaryActionEntersSearchingStateWhenRulesAreValid() throws {
        let tree = try TemporaryFixtureTree.make { try $0.file("report.txt", contents: "report") }
        defer { try? FileManager.default.removeItem(at: tree.rootURL) }
        let environment = SearchFormTestEnvironment()
        let controller = environment.makeFormController()
        _ = controller.view

        controller.applySearchSessionSnapshot(SearchFormTestEnvironment.folderSnapshot(tree.rootURL))
        controller.debugTriggerPrimaryAction()

        #expect(controller.debugPrimaryActionTitle == L10n.string("search_window.action.stop"))
        #expect(controller.debugStatusText == L10n.format("search_window.status.searching", tree.rootURL.lastPathComponent, 0))

        // 立即停止，避免后台搜索在测试结束后继续运行
        controller.debugTriggerPrimaryAction()
        #expect(controller.debugPrimaryActionTitle == L10n.string("search_window.action.find"))
        #expect(environment.searchHistoryStore.all().isEmpty)
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

        let controller = SearchFormViewController(
            scopeProvider: SearchScopeMenuProvider(mountedVolumes: { [] }),
            recentLocationStore: recentLocationStore,
            searchHistoryStore: SearchHistoryStore(storage: storage),
            searchSessionStore: SearchSessionStore(storage: storage),
            settings: AppSettings(storage: storage)
        )
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
            scopeProvider: SearchScopeMenuProvider(mountedVolumes: {
                [SearchScopeMountedVolume(name: "webdav.stun.vanjay.cn", path: "/Volumes/webdav.stun.vanjay.cn")]
            }),
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
            scopeProvider: SearchScopeMenuProvider(mountedVolumes: { [] }),
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
        let environment = SearchFormTestEnvironment()
        environment.settings.tieResultsWindowToFindWindow = true

        let controller = environment.makeFormController()
        _ = controller.view
        defer { closeWindows(titled: ["First", "Second"]) }

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
        let environment = SearchFormTestEnvironment()
        environment.settings.tieResultsWindowToFindWindow = false

        let controller = environment.makeFormController()
        _ = controller.view
        defer { closeWindows(titled: ["First", "Second"]) }

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
        let environment = SearchFormTestEnvironment()
        environment.settings.tieResultsWindowToFindWindow = tieResultsWindow

        let controller = environment.makeFormController()
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
        let environment = SearchFormTestEnvironment()
        let workflowController = environment.workflowController
        let controller = environment.makeFormController()
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
        let environment = SearchFormTestEnvironment()
        let workflowController = environment.workflowController
        let controller = environment.makeFormController()
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
        let controller = SearchFormTestEnvironment().makeFormController()
        _ = controller.view
        defer { closeWindows(titled: ["Name contains report"]) }

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
        let environment = SearchFormTestEnvironment()
        environment.settings.tieResultsWindowToFindWindow = true
        let controller = environment.makeFormController()
        _ = controller.view
        defer { closeWindows(titled: ["Name contains report", "Restored"]) }

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
        let controller = SearchFormTestEnvironment().makeFormController()
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
        let controller = SearchFormTestEnvironment().makeFormController()
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
        let controller = SearchFormTestEnvironment().makeFormController()
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
        let controller = SearchFormTestEnvironment().makeFormController()
        _ = controller.view

        let light = controller.debugRootBackgroundHex(for: .aqua)
        let dark = controller.debugRootBackgroundHex(for: .darkAqua)

        #expect(light != dark)
    }
    // MARK: - 重新搜索（⌘R）

    /// 模拟一次不经过真实执行器的搜索：进入搜索中再结束
    @MainActor
    private func finishSimulatedSearch(_ workflowController: SearchWorkflowController, matchCount: Int) {
        workflowController.onStateChange?(.init(phase: .searching(scopeDescription: "Fixture", matchCount: 0)))
        workflowController.onStateChange?(.init(phase: .idle(matchCount: matchCount)))
    }

    @MainActor
    @Test
    func refreshStaysAvailableWithoutTiedWindowAndRerunsThatWindowsOwnSearch() throws {
        let tree = try TemporaryFixtureTree.make { try $0.file("alpha.txt", contents: "alpha") }
        defer { try? FileManager.default.removeItem(at: tree.rootURL) }
        let environment = SearchFormTestEnvironment()
        environment.settings.tieResultsWindowToFindWindow = false
        let controller = environment.makeFormController()
        _ = controller.view
        defer { closeWindows(titled: ["Refresh A", "Refresh B", "Name contains alpha"]) }

        controller.debugSetLastSearchRequest(
            SearchFormTestEnvironment.request(scopeDescription: "Scope A", rootPath: tree.path, value: "alpha")
        )
        controller.debugOpenResultsWindow(title: "Refresh A")
        let windowA = try #require(controller.debugResultsWindowController)
        finishSimulatedSearch(environment.workflowController, matchCount: 1)
        // 未绑定时搜索结束后查找窗口不再持有结果窗口，但结果窗口仍记得自己的条件
        #expect(controller.debugResultsWindowController == nil)

        // 之后又进行了另一次搜索，lastSearchRequest 已变为 B
        controller.debugSetLastSearchRequest(
            SearchFormTestEnvironment.request(scopeDescription: "Scope B", rootPath: tree.path, value: "beta")
        )
        controller.debugOpenResultsWindow(title: "Refresh B")
        finishSimulatedSearch(environment.workflowController, matchCount: 1)

        #expect(windowA.validateMenuItem(Self.refreshMenuItem))
        windowA.refreshSearchResults(nil)

        // 重新搜索的是窗口 A 自己的条件，结果回到窗口 A
        #expect(controller.isSearching)
        #expect(controller.debugStatusText == L10n.format("search_window.status.searching", "Scope A", 0))
        #expect(controller.debugResultsWindowController === windowA)
        // 搜索中不可再次触发
        #expect(windowA.validateMenuItem(Self.refreshMenuItem) == false)

        controller.debugTriggerPrimaryAction()
        #expect(controller.isSearching == false)
    }

    @MainActor
    @Test
    func refreshBecomesUnavailableAfterFindWindowIsReleased() throws {
        let environment = SearchFormTestEnvironment()
        environment.settings.tieResultsWindowToFindWindow = true
        var resultsWindowController: SearchResultsWindowController?
        weak var weakController: SearchFormViewController?
        defer { closeWindows(titled: ["Released"]) }

        autoreleasepool {
            let controller = environment.makeFormController()
            _ = controller.view
            controller.debugSetLastSearchRequest(
                SearchFormTestEnvironment.request(scopeDescription: "Scope", rootPath: "/tmp", value: "released")
            )
            controller.debugOpenResultsWindow(title: "Released")
            resultsWindowController = controller.debugResultsWindowController
            weakController = controller
        }

        let resultsWindow = try #require(resultsWindowController)
        #expect(weakController == nil)
        #expect(resultsWindow.validateMenuItem(Self.refreshMenuItem) == false)
        // 即使绕过菜单校验直接调用也不会崩溃
        resultsWindow.refreshSearchResults(nil)
    }

    @MainActor
    @Test
    func refreshIsUnavailableForResultsWithoutKnownSearch() throws {
        let controller = SearchFormTestEnvironment().makeFormController()
        _ = controller.view
        defer { closeWindows(titled: ["Unknown"]) }

        controller.debugOpenResultsWindow(title: "Unknown")
        let resultsWindow = try #require(controller.debugResultsWindowController)

        #expect(resultsWindow.validateMenuItem(Self.refreshMenuItem) == false)
    }

    // MARK: - 0 结果

    @MainActor
    @Test
    func searchWithNoResultsClearsTiedResultsWindow() throws {
        let environment = SearchFormTestEnvironment()
        environment.settings.tieResultsWindowToFindWindow = true
        let controller = environment.makeFormController()
        _ = controller.view
        let fooRequest = SearchFormTestEnvironment.request(scopeDescription: "Scope", rootPath: "/tmp", value: "foo")
        let emptyRequest = SearchFormTestEnvironment.request(scopeDescription: "Scope", rootPath: "/tmp", value: "zzzz")
        defer { closeWindows(titled: [fooRequest.queryTitle, emptyRequest.queryTitle]) }

        controller.debugSetLastSearchRequest(fooRequest)
        controller.debugOpenResultsWindow(
            title: fooRequest.queryTitle,
            items: (0..<10).map { SearchResultItem(path: "/tmp/foo-\($0).txt", matchReason: "名称命中", previewSnippet: nil) }
        )
        let resultsWindow = try #require(controller.debugResultsWindowController)
        finishSimulatedSearch(environment.workflowController, matchCount: 10)

        controller.debugSetLastSearchRequest(emptyRequest)
        finishSimulatedSearch(environment.workflowController, matchCount: 0)

        let resultsViewController = try #require(resultsWindow.window?.contentViewController as? SearchResultsViewController)
        #expect(resultsWindow.window?.title == emptyRequest.queryTitle)
        #expect(resultsViewController.debugShowsEmptyState)
        #expect(controller.debugLatestResultsWindowController === resultsWindow)
        #expect(controller.debugShowLastResultsButtonVisible == false)
    }

    @MainActor
    @Test
    func searchWithNoResultsDropsLastResultsWhenNotTied() {
        let environment = SearchFormTestEnvironment()
        environment.settings.tieResultsWindowToFindWindow = false
        let controller = environment.makeFormController()
        _ = controller.view
        defer { closeWindows(titled: ["Not tied"]) }

        controller.debugSetLastSearchRequest(
            SearchFormTestEnvironment.request(scopeDescription: "Scope", rootPath: "/tmp", value: "foo")
        )
        controller.debugOpenResultsWindow(title: "Not tied")
        finishSimulatedSearch(environment.workflowController, matchCount: 1)
        finishSimulatedSearch(environment.workflowController, matchCount: 0)

        // 未绑定时不改动旧窗口，「上次结果」也不再指向更早的搜索
        #expect(NSApp.windows.contains { $0.title == "Not tied" && $0.isVisible })
        #expect(controller.debugLatestResultsWindowController == nil)
    }

    // MARK: - 拖放设置范围

    @MainActor
    @Test
    func droppingFolderOrFileSetsSearchScope() throws {
        let tree = try TemporaryFixtureTree.make { try $0.file("Docs/report.txt", contents: "report") }
        defer { try? FileManager.default.removeItem(at: tree.rootURL) }
        let environment = SearchFormTestEnvironment()
        let controller = environment.makeFormController()
        _ = controller.view
        let folderURL = tree.rootURL.appendingPathComponent("Docs", isDirectory: true)

        #expect(controller.applyDroppedURLs([folderURL]))
        #expect(controller.debugCurrentSearchSessionSnapshot.criteria.scope.representedPath == folderURL.path)
        #expect(controller.debugCurrentSearchSessionSnapshot.criteria.scope.sourceKind == .folder)
        #expect(controller.debugSelectedScopeTitle == L10n.format("search_scope.inside_named_folder", "Docs"))

        // 拖入文件时使用其所在文件夹
        #expect(controller.applyDroppedURLs([tree.rootURL]))
        #expect(controller.applyDroppedURLs([folderURL.appendingPathComponent("report.txt")]))
        #expect(controller.debugCurrentSearchSessionSnapshot.criteria.scope.representedPath == folderURL.path)

        // 与「选择其他文件夹…」一样，开始搜索时记入最近位置
        controller.debugApplySelectionsThroughRulesEditor([SearchRuleSelection(field: .name, operator: .contains, value: "report")])
        controller.debugTriggerPrimaryAction()
        controller.debugTriggerPrimaryAction()
        #expect(environment.recentLocationStore.all().contains { $0.scope.representedPath == folderURL.path })
    }

    @MainActor
    @Test
    func droppingIsRejectedWhileSearchingOrWithoutFileURLs() throws {
        let tree = try TemporaryFixtureTree.make { try $0.file("Docs/report.txt", contents: "report") }
        defer { try? FileManager.default.removeItem(at: tree.rootURL) }
        let environment = SearchFormTestEnvironment()
        let controller = environment.makeFormController()
        _ = controller.view
        let originalScope = controller.debugCurrentSearchSessionSnapshot.criteria.scope

        #expect(controller.applyDroppedURLs([]) == false)
        #expect(controller.applyDroppedURLs([try #require(URL(string: "https://example.com"))]) == false)

        environment.workflowController.onStateChange?(.init(phase: .searching(scopeDescription: "Fixture", matchCount: 0)))
        #expect(controller.applyDroppedURLs([tree.rootURL]) == false)
        #expect(controller.debugCurrentSearchSessionSnapshot.criteria.scope == originalScope)
        environment.workflowController.onStateChange?(.init(phase: .idle(matchCount: 0)))
    }

    @MainActor
    @Test
    func dropViewTogglesHighlight() {
        let dropView = SearchFormDropView()
        dropView.installDropHighlight()
        #expect(dropView.isDropHighlighted == false)

        dropView.setDropHighlighted(true)
        #expect(dropView.isDropHighlighted)

        dropView.setDropHighlighted(false)
        #expect(dropView.isDropHighlighted == false)
    }

    // MARK: - 卷宗

    @MainActor
    @Test
    func sameNamedVolumesAppearAsSeparateScopes() {
        let controller = SearchFormTestEnvironment().makeFormController(mountedVolumes: [
            SearchScopeMountedVolume(name: "Untitled", path: "/Volumes/Untitled"),
            SearchScopeMountedVolume(name: "Untitled", path: "/Volumes/Untitled 1")
        ])
        _ = controller.view

        let volumeTitles = controller.debugScopeTitles.filter { $0.contains("Untitled") }
        #expect(volumeTitles.count == 2)
        #expect(Set(volumeTitles).count == 2)
    }

    // MARK: - 无障碍

    @MainActor
    @Test
    func accessibilityLabelsUseLocalizedTextInsteadOfTestIdentifiers() {
        let row = SearchRuleRowView()
        #expect(row.addButton.accessibilityLabel() == L10n.string("search_rule.accessibility.add"))
        #expect(row.removeButton.accessibilityLabel() == L10n.string("search_rule.accessibility.remove"))
        #expect(row.addButton.accessibilityIdentifier() == "SearchRuleAddButton")

        let listView = SearchRuleListView()
        #expect(listView.accessibilityLabel() == L10n.string("search_window.accessibility.rules"))
        #expect(listView.accessibilityIdentifier() == "SearchRulesPanel")
    }
}
