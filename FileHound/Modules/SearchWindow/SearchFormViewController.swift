import AppKit
import SnapKit

@MainActor
final class SearchFormViewController: NSViewController {
    enum Layout {
        static let horizontalMargin: CGFloat = 20
        static let topMargin: CGFloat = 16
        static let bottomMargin: CGFloat = 20
        static let headerSpacing: CGFloat = 12
        static let sectionSpacing: CGFloat = 16
        /// 顶部范围弹出菜单与底部查找按钮所在行的高度，与规则行控件同高。
        static let barHeight: CGFloat = SearchRuleRowView.Layout.controlHeight
        /// 规则面板以外的固定高度：上下边距 + 顶栏 + 底栏 + 两段间距。
        static let chromeHeight: CGFloat = topMargin + barHeight + sectionSpacing + sectionSpacing + barHeight + bottomMargin
        /// 单条规则时的面板高度。
        static let minimumRuleAreaHeight: CGFloat = SearchRuleRowView.Layout.controlHeight
            + SearchRuleRowView.Layout.verticalPadding * 2
            + SearchRuleListView.verticalInset * 2
    }

    weak var windowLayoutDelegate: SearchWindowLayoutDelegate?

    private let scopePopup = NSPopUpButton()
    private let rulesViewController = SearchRulesViewController()
    private let statusLabel = NSTextField(labelWithString: "")
    private let activityIndicator = NSProgressIndicator()
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "")
    private let whereLabel = NSTextField(labelWithString: "")
    private let workflowController: SearchWorkflowController
    private var scopeProvider: SearchScopeMenuProvider
    private let scopeResolver: SearchScopeResolver
    private let recentLocationStore: RecentLocationStore
    private let searchHistoryStore: SearchHistoryStore
    private let searchSessionStore: SearchSessionStore
    private let settings: AppSettings
    private var scopeItems: [SearchScopeMenuItem] = []
    private var scopeItemsByIdentifier: [String: SearchScopeMenuItem] = [:]
    private var resultsWindowController: SearchResultsWindowController?
    private var lastSearchRequest: SearchRequest?
    private var lastConfirmedScopeIdentifier: String?
    private var rulesHeightConstraint: Constraint?
    private var customFolderScopeItem: SearchScopeMenuItem?
    private var lastSubmittedSessionSnapshot: SearchSessionSnapshot?
    private var didCancelCurrentSearch = false
    private var didOpenResultsForCurrentSearch = false
    /// 新建的查找窗口（⌘N）以空白条件开始，只有首个窗口按偏好恢复上次搜索
    private let restoresPreviousSession: Bool

    private var state = SearchWindowState(phase: .idle(matchCount: 0)) {
        didSet {
            render(state)
            handleStateTransition(from: oldValue, to: state)
        }
    }

    init(
        workflowController: SearchWorkflowController = SearchWorkflowController(),
        scopeProvider: SearchScopeMenuProvider = SearchScopeMenuProvider(),
        scopeResolver: SearchScopeResolver = SearchScopeResolver(),
        recentLocationStore: RecentLocationStore = .shared,
        searchHistoryStore: SearchHistoryStore = .shared,
        searchSessionStore: SearchSessionStore = .shared,
        settings: AppSettings = .shared,
        restoresPreviousSession: Bool = true
    ) {
        self.workflowController = workflowController
        self.scopeProvider = scopeProvider
        self.scopeResolver = scopeResolver
        self.recentLocationStore = recentLocationStore
        self.searchHistoryStore = searchHistoryStore
        self.searchSessionStore = searchSessionStore
        self.settings = settings
        self.restoresPreviousSession = restoresPreviousSession
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = AppearanceAwareView()
        rootView.backgroundColorProvider = { _ in .windowBackgroundColor }

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        whereLabel.font = .systemFont(ofSize: 16, weight: .regular)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        whereLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        whereLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor

        scopePopup.setAccessibilityIdentifier("SearchScopePopup")
        scopePopup.setAccessibilityLabel("SearchScopePopup")
        scopePopup.font = .systemFont(ofSize: 14, weight: .regular)
        scopePopup.controlSize = .large
        primaryButton.controlSize = .large
        primaryButton.font = .systemFont(ofSize: 14, weight: .medium)
        scopePopup.imagePosition = .imageLeft
        statusLabel.setAccessibilityIdentifier("SearchStatusLabel")
        primaryButton.setAccessibilityIdentifier("PrimarySearchButton")
        activityIndicator.setAccessibilityIdentifier("SearchActivityIndicator")
        activityIndicator.setAccessibilityLabel("SearchActivityIndicator")

        primaryButton.target = self
        primaryButton.action = #selector(primaryButtonPressed)
        primaryButton.keyEquivalent = "\r"
        scopePopup.target = self
        scopePopup.action = #selector(scopeSelectionChanged)

        activityIndicator.style = .spinning
        activityIndicator.controlSize = .small
        activityIndicator.isDisplayedWhenStopped = false

        addChild(rulesViewController)
        [titleLabel, scopePopup, whereLabel, rulesViewController.view, statusLabel, activityIndicator, primaryButton].forEach(rootView.addSubview)

        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(Layout.horizontalMargin)
            make.centerY.equalTo(scopePopup)
        }
        scopePopup.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.trailing).offset(Layout.headerSpacing)
            make.top.equalToSuperview().inset(Layout.topMargin)
            make.height.equalTo(Layout.barHeight)
        }
        whereLabel.snp.makeConstraints { make in
            make.leading.equalTo(scopePopup.snp.trailing).offset(Layout.headerSpacing)
            make.trailing.equalToSuperview().inset(Layout.horizontalMargin)
            make.centerY.equalTo(scopePopup)
        }
        rulesViewController.view.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(Layout.horizontalMargin)
            make.top.equalTo(scopePopup.snp.bottom).offset(Layout.sectionSpacing)
            self.rulesHeightConstraint = make.height.equalTo(Layout.minimumRuleAreaHeight).constraint
        }
        primaryButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(Layout.horizontalMargin)
            make.top.equalTo(rulesViewController.view.snp.bottom).offset(Layout.sectionSpacing)
            make.width.equalTo(120)
            make.height.equalTo(Layout.barHeight)
        }
        activityIndicator.snp.makeConstraints { make in
            make.trailing.equalTo(primaryButton.snp.leading).offset(-10)
            make.centerY.equalTo(primaryButton)
        }
        statusLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(Layout.horizontalMargin)
            make.trailing.lessThanOrEqualTo(activityIndicator.snp.leading).offset(-12)
            make.centerY.equalTo(primaryButton)
        }

        workflowController.onStateChange = { [weak self] state in
            self?.state = state
        }
        workflowController.onResults = { [weak self] title, items in
            self?.openResultsWindow(title: title, items: items)
        }
        rulesViewController.onContentLayoutChange = { [weak self] contentHeight in
            self?.windowLayoutDelegate?.searchFormViewController(self, desiredRulesContentHeight: contentHeight)
        }
        rulesViewController.onSelectionsChange = { [weak self] _ in
            self?.searchCriteriaDidChange()
        }

        view = rootView
        reloadLocalizedStrings()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureScopePopup()

        if restoresPreviousSession,
           settings.restorePreviousSearch,
           let snapshot = searchSessionStore.load() {
            applySearchSessionSnapshot(snapshot)
        }

        render(state)
        windowLayoutDelegate?.searchFormViewController(self, desiredRulesContentHeight: rulesViewController.preferredContentHeight)

        if ProcessInfo.processInfo.arguments.contains("--fixture-results") {
            let items = workflowController.fixtureItems()
            openResultsWindow(title: "Name contains report", items: items)
            if let fixturePresentationState = fixtureResultsPresentationState() {
                resultsWindowController?.apply(presentationState: fixturePresentationState)
            }
            state = .init(phase: .idle(matchCount: items.count))
        }
    }

    private func fixtureResultsPresentationState() -> ResultPresentationState? {
        let arguments = ProcessInfo.processInfo.arguments
        var presentationState = ResultPresentationState()
        var didCustomizeState = false

        if arguments.contains("--fixture-results-table-mode") {
            presentationState.mode = .table
            didCustomizeState = true
        } else if arguments.contains("--fixture-results-tree-mode") {
            presentationState.mode = .tree
            didCustomizeState = true
        } else if arguments.contains("--fixture-results-grid-mode") {
            presentationState.mode = .grid
            didCustomizeState = true
        }

        if arguments.contains("--fixture-results-filter-report") {
            presentationState.filterText = "report"
            didCustomizeState = true
        }

        return didCustomizeState ? presentationState : nil
    }

    private func configureScopePopup(selecting scopeItem: SearchScopeMenuItem? = nil) {
        scopeProvider.recentLocations = recentLocationStore.all()
        let sections = currentScopeSections()
        var indexedItems: [(identifier: String, item: SearchScopeMenuItem)] = []
        var nextItemIndex = 0

        let menu = NSMenu()
        var selectedMenuItem: NSMenuItem?

        for (sectionIndex, section) in sections.enumerated() {
            guard section.items.isEmpty == false else {
                continue
            }

            if sectionIndex > 0 {
                menu.addItem(.separator())
            }

            if let title = section.title {
                let headerItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                headerItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
                menu.addItem(headerItem)
            }

            for item in section.items {
                let menuIdentifier = "scope-item-\(nextItemIndex)"
                nextItemIndex += 1
                indexedItems.append((identifier: menuIdentifier, item: item))

                let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: item.keyEquivalent)
                menuItem.identifier = NSUserInterfaceItemIdentifier(menuIdentifier)
                menuItem.image = item.icon?.scopeMenuScaled()
                if item.keyEquivalent.isEmpty == false {
                    menuItem.keyEquivalentModifierMask = [.command]
                }
                menu.addItem(menuItem)

                if let scopeItem, matches(item, preferredScope: scopeItem) {
                    selectedMenuItem = menuItem
                }
            }
        }

        scopeItems = indexedItems.map(\.item)
        scopeItemsByIdentifier = Dictionary(uniqueKeysWithValues: indexedItems.map { ($0.identifier, $0.item) })
        scopePopup.menu = menu

        if let selectedMenuItem {
            scopePopup.select(selectedMenuItem)
            lastConfirmedScopeIdentifier = selectedMenuItem.identifier?.rawValue
            return
        }

        if let firstSelectableItem = menu.items.first(where: { $0.isEnabled }) {
            scopePopup.select(firstSelectableItem)
            lastConfirmedScopeIdentifier = firstSelectableItem.identifier?.rawValue
        }
    }

    @objc
    private func primaryButtonPressed() {
        switch state.phase {
        case .searching:
            didCancelCurrentSearch = true
            workflowController.cancel()
        default:
            guard rulesViewController.validationSummary.canSearch else {
                render(state)
                return
            }

            let scopeItem = selectedScopeItem()
            let criteriaSnapshot = SearchCriteriaSnapshot(
                scope: scopeItem.snapshot,
                rules: rulesViewController.currentSelections
            )
            let resolvedScope = scopeResolver.resolve(scopeItem.snapshot)
            let request = SearchRequest(
                scopeDescription: scopeItem.scopeDescription,
                rootPaths: resolvedScope.rootPaths,
                excludedPaths: resolvedScope.excludedPaths,
                rules: rulesViewController.currentSelections
            )
            lastSearchRequest = request
            lastSubmittedSessionSnapshot = SearchSessionSnapshot(criteria: criteriaSnapshot)
            didOpenResultsForCurrentSearch = false
            rememberRecentLocationIfNeeded(scopeItem)
            workflowController.start(request: request, preferences: settings.searchExecutionPreferences)
        }
    }

    @objc
    private func scopeSelectionChanged() {
        let item = selectedScopeItem()
        guard item.kind == .folderPicker else {
            lastConfirmedScopeIdentifier = scopePopup.selectedItem?.identifier?.rawValue
            searchCriteriaDidChange()
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.string("search_window.choose")

        if panel.runModal() == .OK, let url = panel.url {
            let title = L10n.format("search_scope.inside_named_folder", url.lastPathComponent)
            let updated = SearchScopeMenuItem(
                title: title,
                representedPath: url.path,
                scopeDescription: url.lastPathComponent,
                kind: .folderPicker,
                sourceKind: .folder
            )
            customFolderScopeItem = updated
            configureScopePopup(selecting: updated)
            lastConfirmedScopeIdentifier = scopePopup.selectedItem?.identifier?.rawValue
            searchCriteriaDidChange()
            return
        }

        selectScopeItem(withIdentifier: lastConfirmedScopeIdentifier)
    }

    private func selectedScopeItem() -> SearchScopeMenuItem {
        guard
            let identifier = scopePopup.selectedItem?.identifier?.rawValue,
            let item = scopeItemsByIdentifier[identifier]
        else {
            return scopeItems.first ?? SearchScopeMenuProvider().sections().flatMap(\.items).first!
        }

        return item
    }

    private func rememberRecentLocationIfNeeded(_ scopeItem: SearchScopeMenuItem) {
        switch scopeItem.sourceKind {
        case .folder, .mountedVolume, .recentLocation:
            try? recentLocationStore.remember(scope: scopeItem.snapshot)
            configureScopePopup(selecting: scopeItem)
        case .preset:
            break
        }
    }

    private func render(_ state: SearchWindowState) {
        let blockingMessage = state.phase.isSearching ? nil : rulesViewController.validationSummary.firstBlockingMessage
        let statusText = blockingMessage ?? state.statusText
        statusLabel.stringValue = statusText
        statusLabel.setAccessibilityLabel(statusText)
        primaryButton.title = state.primaryActionTitle
        primaryButton.setAccessibilityLabel(state.primaryActionTitle)
        scopePopup.isEnabled = state.isEditingEnabled
        rulesViewController.setEnabled(state.isEditingEnabled)
        primaryButton.isEnabled = state.phase.isSearching || rulesViewController.validationSummary.canSearch

        if state.showsActivityIndicator {
            activityIndicator.startAnimation(nil)
        } else {
            activityIndicator.stopAnimation(nil)
        }
    }

    private func handleStateTransition(from oldValue: SearchWindowState, to newValue: SearchWindowState) {
        guard oldValue.phase.isSearching, newValue.phase.isSearching == false else {
            return
        }

        if didOpenResultsForCurrentSearch {
            resultsWindowController?.searchStatus = didCancelCurrentSearch ? .stopped : .finished
        }

        defer {
            didCancelCurrentSearch = false
            didOpenResultsForCurrentSearch = false
            if settings.tieResultsWindowToFindWindow == false {
                resultsWindowController = nil
            }
        }

        guard didCancelCurrentSearch == false,
              var snapshot = lastSubmittedSessionSnapshot else {
            return
        }

        snapshot.presentationState = currentPresentationState()
        lastSubmittedSessionSnapshot = snapshot

        try? searchSessionStore.save(snapshot)
        try? searchHistoryStore.record(
            RecentSearchRecord(
                title: snapshot.criteria.querySummary,
                criteria: snapshot.criteria,
                presentationState: snapshot.presentationState,
                resultCount: resultCount(from: newValue.phase)
            )
        )

        if settings.openRecentSearchMenu {
            NSApp.mainMenu = MainMenuBuilder(target: NSApp.delegate as AnyObject, settings: settings, searchHistoryStore: searchHistoryStore).build()
        }
    }

    private func resultCount(from phase: SearchWindowPhase) -> Int? {
        switch phase {
        case .idle(let matchCount):
            return matchCount
        case .editing(let matchCount):
            return matchCount
        case .searching:
            return nil
        }
    }

    func reloadLocalizedStrings() {
        titleLabel.stringValue = L10n.string("search_window.find_items")
        whereLabel.stringValue = L10n.string("search_window.where")
        rulesViewController.reloadLocalizedStrings()
        let currentScope = scopeItems.isEmpty ? nil : selectedScopeItem()
        configureScopePopup(selecting: currentScope)
        render(state)
    }

    private func openResultsWindow(title: String, items: [SearchResultItem]) {
        let shouldReuseExistingWindow = resultsWindowController != nil && (
            settings.tieResultsWindowToFindWindow || state.phase.isSearching
        )

        if shouldReuseExistingWindow,
           let existing = resultsWindowController {
            if didOpenResultsForCurrentSearch == false,
               let presentationState = lastSubmittedSessionSnapshot?.presentationState {
                existing.apply(presentationState: presentationState)
            }
            existing.expandsFoldersWhenShowingResults = settings.expandFoldersWhenShowingResults
            existing.searchStatus = searchStatusForResultsWindow
            existing.update(title: title, items: items)
            // 搜索中结果持续刷新，只在本次搜索首次展示时前置窗口，避免反复抢占焦点
            if didOpenResultsForCurrentSearch == false {
                existing.showWindow(nil)
            }
            didOpenResultsForCurrentSearch = true
            return
        }

        guard items.isEmpty == false else {
            return
        }

        let viewModel = SearchResultsViewModel()
        if let presentationState = lastSubmittedSessionSnapshot?.presentationState {
            viewModel.apply(presentationState: presentationState)
        }
        viewModel.title = title
        viewModel.items = items
        viewModel.searchStatus = searchStatusForResultsWindow

        let controller = SearchResultsWindowController(
            viewModel: viewModel,
            title: title,
            expandFoldersWhenShowingResults: settings.expandFoldersWhenShowingResults,
            refreshHandler: { [weak self] in
                self?.refreshLastSearchIfNeeded()
            }
        )
        controller.showWindow(nil)
        resultsWindowController = controller
        didOpenResultsForCurrentSearch = true
    }

    /// 结果页在搜索进行中（提前显示结果）打开或更新时标记为搜索中，搜索结束后由 handleStateTransition 更新
    private var searchStatusForResultsWindow: SearchResultsViewModel.SearchStatus {
        state.phase.isSearching ? .searching : .finished
    }

    private func refreshLastSearchIfNeeded() {
        guard state.phase.isSearching == false,
              let lastSearchRequest,
              resultsWindowController?.window?.isVisible == true else {
            return
        }

        workflowController.start(request: lastSearchRequest, preferences: settings.searchExecutionPreferences)
    }

    var isSearching: Bool {
        state.phase.isSearching
    }

    /// 查找窗口被释放前调用，确保结果窗口状态更新为「已停止」而不是一直停留在「搜索中」
    func cancelSearchIfNeeded() {
        guard state.phase.isSearching else {
            return
        }
        didCancelCurrentSearch = true
        workflowController.cancel()
    }

    /// 判断窗口是否为本查找窗口打开的结果窗口，用于从结果窗口反查当前活跃的查找窗口
    func ownsResultsWindow(_ window: NSWindow) -> Bool {
        resultsWindowController?.window === window
    }

    func applyRuleAreaLayout(height: CGFloat, shouldScroll: Bool) {
        rulesHeightConstraint?.update(offset: height)
        rulesViewController.setScrollingEnabled(shouldScroll)
        view.layoutSubtreeIfNeeded()
    }

    var preferredRulesContentHeight: CGFloat {
        rulesViewController.preferredContentHeight
    }

    func currentSearchSessionSnapshot() -> SearchSessionSnapshot {
        SearchSessionSnapshot(
            criteria: SearchCriteriaSnapshot(
                scope: selectedScopeItem().snapshot,
                rules: rulesViewController.currentSelections
            ),
            presentationState: currentPresentationState()
        )
    }

    func applySearchSessionSnapshot(_ snapshot: SearchSessionSnapshot) {
        lastSubmittedSessionSnapshot = snapshot
        didOpenResultsForCurrentSearch = false
        let scopeItem = SearchScopeMenuItem(
            title: snapshot.criteria.scope.title,
            representedPath: snapshot.criteria.scope.representedPath,
            scopeDescription: snapshot.criteria.scope.scopeDescription,
            kind: snapshot.criteria.scope.sourceKind == .folder ? .folderPicker : .standard,
            sourceKind: snapshot.criteria.scope.sourceKind
        )

        if scopeItem.kind == .folderPicker {
            customFolderScopeItem = scopeItem
        }

        configureScopePopup(selecting: scopeItem)
        rulesViewController.applySelections(snapshot.criteria.rules)
        state = .init(phase: .editing(matchCount: nil))
    }

    private func currentScopeSections() -> [SearchScopeMenuSection] {
        var sections = scopeProvider.sections()
        guard let customFolderScopeItem else {
            return sections
        }

        for index in sections.indices {
            guard let folderPickerIndex = sections[index].items.firstIndex(where: { $0.kind == .folderPicker }) else {
                continue
            }

            var items = sections[index].items
            items[folderPickerIndex] = customFolderScopeItem
            sections[index] = SearchScopeMenuSection(title: sections[index].title, items: items)
            break
        }

        return sections
    }

    private func matches(_ item: SearchScopeMenuItem, preferredScope: SearchScopeMenuItem) -> Bool {
        item.kind == preferredScope.kind &&
        item.sourceKind == preferredScope.sourceKind &&
        item.representedPath == preferredScope.representedPath &&
        item.scopeDescription == preferredScope.scopeDescription
    }

    private func selectScopeItem(withIdentifier identifier: String?) {
        guard
            let identifier,
            let menuItem = scopePopup.menu?.items.first(where: { $0.identifier?.rawValue == identifier })
        else {
            return
        }

        scopePopup.select(menuItem)
    }

    private func currentPresentationState() -> ResultPresentationState? {
        resultsWindowController?.currentPresentationState ?? lastSubmittedSessionSnapshot?.presentationState
    }

    private func searchCriteriaDidChange() {
        guard state.phase.isSearching == false else {
            return
        }

        switch state.phase {
        case .idle(let matchCount):
            state = .init(phase: .editing(matchCount: matchCount))
        case .editing:
            render(state)
        case .searching:
            break
        }
    }
}

#if DEBUG
extension SearchFormViewController {
    func debugTriggerPrimaryAction() {
        primaryButtonPressed()
    }

    var debugPrimaryActionTitle: String {
        primaryButton.title
    }

    var debugPrimaryActionEnabled: Bool {
        primaryButton.isEnabled
    }

    var debugStatusText: String {
        statusLabel.stringValue
    }

    var debugScopeTitles: [String] {
        scopeItems.map(\.title)
    }

    var debugSelectedScopeTitle: String? {
        scopePopup.selectedItem?.title
    }

    var debugCurrentSelections: [SearchRuleSelection] {
        rulesViewController.currentSelections
    }

    func debugApplySelectionsThroughRulesEditor(_ selections: [SearchRuleSelection]) {
        rulesViewController.applySelections(selections)
    }

    func debugOpenResultsWindow(
        title: String = "Name contains report",
        items: [SearchResultItem] = [
            SearchResultItem(path: "/tmp/report.txt", matchReason: "名称命中", previewSnippet: "report")
        ]
    ) {
        openResultsWindow(title: title, items: items)
    }

    var debugResultsWindowIdentifier: ObjectIdentifier? {
        resultsWindowController.map(ObjectIdentifier.init)
    }

    var debugResultsPresentationState: ResultPresentationState? {
        resultsWindowController?.currentPresentationState
    }

    var debugCurrentSearchSessionSnapshot: SearchSessionSnapshot {
        currentSearchSessionSnapshot()
    }

    func debugRootBackgroundHex(for appearanceName: NSAppearance.Name) -> String {
        NSColor.windowBackgroundColor.fhResolvedHex(for: appearanceName)
    }
}
#endif
