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
    private let showLastResultsButton = NSButton(title: "", target: nil, action: nil)
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
    /// 最近一次搜索的结果窗口；不随「结果窗口绑定查找窗口」偏好释放，关闭后可通过「显示上次结果」重新打开
    private var latestResultsWindowController: SearchResultsWindowController? {
        didSet {
            guard oldValue !== latestResultsWindowController else { return }
            observeLatestResultsWindow(old: oldValue?.window, new: latestResultsWindowController?.window)
        }
    }
    private var statusTrailingToShowLastResultsConstraint: Constraint?
    /// 搜索中按钮与转圈指示器同时显示时，指示器让到按钮左侧
    private var activityIndicatorTrailingToShowLastResultsConstraint: Constraint?
    private var activityIndicatorTrailingToPrimaryConstraint: Constraint?
    private var lastSearchRequest: SearchRequest?
    /// 每个结果窗口各自记住产生它的搜索条件，⌘R 按该窗口自己的条件重新搜索（绑定复用时随新搜索更新）
    private var searchesByResultsWindow: [ObjectIdentifier: ResultsWindowSearch] = [:]
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
        let rootView = SearchFormDropView()

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        whereLabel.font = .systemFont(ofSize: 16, weight: .regular)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        whereLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        whereLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor

        // identifier 留给 UI 测试定位，无障碍标签在 reloadLocalizedStrings 中使用本地化文案
        scopePopup.setAccessibilityIdentifier("SearchScopePopup")
        scopePopup.font = .systemFont(ofSize: 14, weight: .regular)
        scopePopup.controlSize = .large
        primaryButton.controlSize = .large
        primaryButton.font = .systemFont(ofSize: 14, weight: .medium)
        showLastResultsButton.controlSize = .large
        showLastResultsButton.font = .systemFont(ofSize: 14, weight: .regular)
        showLastResultsButton.isHidden = true
        showLastResultsButton.setContentHuggingPriority(.required, for: .horizontal)
        showLastResultsButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        showLastResultsButton.setAccessibilityIdentifier("ShowLastResultsButton")
        scopePopup.imagePosition = .imageLeft
        statusLabel.setAccessibilityIdentifier("SearchStatusLabel")
        primaryButton.setAccessibilityIdentifier("PrimarySearchButton")
        activityIndicator.setAccessibilityIdentifier("SearchActivityIndicator")

        primaryButton.target = self
        primaryButton.action = #selector(primaryButtonPressed)
        primaryButton.keyEquivalent = "\r"
        showLastResultsButton.target = self
        showLastResultsButton.action = #selector(showLastResultsPressed)
        scopePopup.target = self
        scopePopup.action = #selector(scopeSelectionChanged)

        activityIndicator.style = .spinning
        activityIndicator.controlSize = .small
        activityIndicator.isDisplayedWhenStopped = false

        addChild(rulesViewController)
        [titleLabel, scopePopup, whereLabel, rulesViewController.view, statusLabel, activityIndicator, showLastResultsButton, primaryButton].forEach(rootView.addSubview)
        // 高亮层需盖在所有控件之上，必须在控件添加完之后安装
        rootView.installDropHighlight()
        rootView.canAcceptDrop = { [weak self] in
            self?.state.isEditingEnabled ?? false
        }
        rootView.onDropURLs = { [weak self] urls in
            self?.applyDroppedURLs(urls) ?? false
        }

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
            self.activityIndicatorTrailingToPrimaryConstraint = make.trailing
                .equalTo(primaryButton.snp.leading).offset(-10)
                .constraint
            make.centerY.equalTo(primaryButton)
            self.activityIndicatorTrailingToShowLastResultsConstraint = make.trailing
                .equalTo(showLastResultsButton.snp.leading).offset(-10)
                .constraint
        }
        activityIndicatorTrailingToShowLastResultsConstraint?.deactivate()
        // 与转圈指示器共用同一位置；显示按钮时指示器改为贴在按钮左侧，两条指示器约束互斥切换
        showLastResultsButton.snp.makeConstraints { make in
            make.trailing.equalTo(primaryButton.snp.leading).offset(-8)
            make.centerY.equalTo(primaryButton)
            make.height.equalTo(Layout.barHeight)
        }
        statusLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(Layout.horizontalMargin)
            make.trailing.lessThanOrEqualTo(activityIndicator.snp.leading).offset(-12)
            make.centerY.equalTo(primaryButton)
            self.statusTrailingToShowLastResultsConstraint = make.trailing
                .lessThanOrEqualTo(showLastResultsButton.snp.leading).offset(-12)
                .constraint
        }
        statusTrailingToShowLastResultsConstraint?.deactivate()

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
        observeMountedVolumeChanges()

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
            applyChosenFolder(url)
            return
        }

        selectScopeItem(withIdentifier: lastConfirmedScopeIdentifier)
    }

    /// 「选择其他文件夹…」与拖放共用：把文件夹设为搜索范围，开始搜索时与其他范围一样记入最近位置
    private func applyChosenFolder(_ url: URL) {
        let folderName = url.lastPathComponent
        let title = L10n.format("search_scope.inside_named_folder", folderName)
        let updated = SearchScopeMenuItem(
            title: title,
            representedPath: url.path,
            scopeDescription: folderName,
            kind: .folderPicker,
            sourceKind: .folder
        )
        customFolderScopeItem = updated
        configureScopePopup(selecting: updated)
        lastConfirmedScopeIdentifier = scopePopup.selectedItem?.identifier?.rawValue
        searchCriteriaDidChange()
    }

    /// 处理从访达拖入的文件 URL；搜索中不可修改范围，返回 false 表示拒绝本次拖放
    @discardableResult
    func applyDroppedURLs(_ urls: [URL]) -> Bool {
        guard state.isEditingEnabled,
              let folderURL = SearchScopeDropResolver.folderURL(from: urls) else {
            return false
        }

        applyChosenFolder(folderURL)
        return true
    }

    /// 插拔磁盘、卷宗改名后重建范围菜单，保持当前选择不变（被卸载的卷宗除外）
    private func observeMountedVolumeChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ].forEach {
            workspaceCenter.addObserver(self, selector: #selector(mountedVolumesDidChange(_:)), name: $0, object: nil)
        }
    }

    @objc
    private func mountedVolumesDidChange(_ notification: Notification) {
        configureScopePopup(selecting: selectedScopeItem())
    }

    @objc
    private func showLastResultsPressed() {
        // 搜索中：本次搜索尚未展示过结果时，先展示已找到的条目，后续进度继续刷新结果页
        if state.phase.isSearching, didOpenResultsForCurrentSearch == false {
            workflowController.revealResults()
            renderShowLastResultsButton()
            return
        }

        guard let window = latestResultsWindowController?.window else {
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        latestResultsWindowController?.showWindow(nil)
        render(state)
    }

    private func selectedScopeItem() -> SearchScopeMenuItem {
        guard
            let identifier = scopePopup.selectedItem?.identifier?.rawValue,
            let item = scopeItemsByIdentifier[identifier]
        else {
            return scopeItems.first ?? SearchScopeMenuProvider(mountedVolumes: { [] }).sections().flatMap(\.items).first!
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
        renderShowLastResultsButton()

        if state.showsActivityIndicator {
            activityIndicator.startAnimation(nil)
        } else {
            activityIndicator.stopAnimation(nil)
        }
    }

    /// 非搜索状态：上次结果窗口被关闭或最小化时显示「显示上次结果」。
    /// 搜索中：已有匹配项但本次搜索的结果窗口不可见时显示「显示结果」。
    /// willClose 发出时窗口仍处于可见状态，此时由调用方传入 latestWindowIsClosing 视为已关闭
    private func renderShowLastResultsButton(latestWindowIsClosing: Bool = false) {
        func isOnScreen(_ window: NSWindow?) -> Bool {
            guard let window else { return false }
            return latestWindowIsClosing == false && window.isVisible && window.isMiniaturized == false
        }

        let isHidden: Bool
        switch state.phase {
        case .searching(_, let matchCount):
            isHidden = matchCount == 0 || (
                didOpenResultsForCurrentSearch && isOnScreen(latestResultsWindowController?.window)
            )
        case .idle, .editing:
            isHidden = latestResultsWindowController == nil || isOnScreen(latestResultsWindowController?.window)
        }

        let title = L10n.string(
            state.phase.isSearching ? "search_window.action.show_results" : "search_window.action.show_last_results"
        )
        showLastResultsButton.title = title
        showLastResultsButton.setAccessibilityLabel(title)
        showLastResultsButton.isHidden = isHidden
        showLastResultsButton.toolTip = state.phase.isSearching ? nil : latestResultsWindowController?.window?.title
        if isHidden {
            statusTrailingToShowLastResultsConstraint?.deactivate()
            activityIndicatorTrailingToShowLastResultsConstraint?.deactivate()
            activityIndicatorTrailingToPrimaryConstraint?.activate()
        } else {
            activityIndicatorTrailingToPrimaryConstraint?.deactivate()
            statusTrailingToShowLastResultsConstraint?.activate()
            activityIndicatorTrailingToShowLastResultsConstraint?.activate()
        }
    }

    private func observeLatestResultsWindow(old oldWindow: NSWindow?, new newWindow: NSWindow?) {
        let center = NotificationCenter.default
        let names: [NSNotification.Name] = [
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]

        if let oldWindow {
            names.forEach { center.removeObserver(self, name: $0, object: oldWindow) }
        }
        if let newWindow {
            names.forEach {
                center.addObserver(self, selector: #selector(latestResultsWindowVisibilityChanged(_:)), name: $0, object: newWindow)
            }
        }
        render(state)
    }

    @objc
    private func latestResultsWindowVisibilityChanged(_ notification: Notification) {
        renderShowLastResultsButton(latestWindowIsClosing: notification.name == NSWindow.willCloseNotification)
    }

    private func handleStateTransition(from oldValue: SearchWindowState, to newValue: SearchWindowState) {
        guard oldValue.phase.isSearching, newValue.phase.isSearching == false else {
            return
        }

        if didOpenResultsForCurrentSearch {
            resultsWindowController?.searchStatus = didCancelCurrentSearch ? .stopped : .finished
        } else if didCancelCurrentSearch == false {
            showEmptyResultsInBoundWindowIfNeeded()
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

        // 「最近搜索」子菜单在 menuNeedsUpdate 中按需从历史读取，这里不需要重建主菜单
    }

    /// 本次搜索正常结束但没有结果：已绑定的结果窗口仍显示上一次搜索的条目和标题，
    /// 这里把它清空为本次搜索的空状态，避免误以为是本次结果；「上次结果」不再指向更早的搜索
    private func showEmptyResultsInBoundWindowIfNeeded() {
        guard let existing = resultsWindowController, let lastSearchRequest else {
            latestResultsWindowController = nil
            return
        }

        existing.searchStatus = .finished
        existing.update(title: lastSearchRequest.queryTitle, items: [])
        bindCurrentSearch(to: existing)
        // 窗口仍打开（含最小化）时它已代表本次搜索；已被关闭的窗口不再作为「上次结果」
        let isWindowOpen = existing.window.map { $0.isVisible || $0.isMiniaturized } ?? false
        latestResultsWindowController = isWindowOpen ? existing : nil
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
        scopePopup.setAccessibilityLabel(L10n.string("search_window.accessibility.scope"))
        activityIndicator.setAccessibilityLabel(L10n.string("search_window.accessibility.searching"))
        rulesViewController.reloadLocalizedStrings()
        let currentScope = scopeItems.isEmpty ? nil : selectedScopeItem()
        configureScopePopup(selecting: currentScope)
        render(state)
    }

    private func openResultsWindow(title: String, items: [SearchResultItem]) {
        defer {
            if didOpenResultsForCurrentSearch, let resultsWindowController {
                bindCurrentSearch(to: resultsWindowController)
            }
            renderShowLastResultsButton()
        }

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
            // 同一次搜索的后续进度合并进结果页，保留用户在搜索中做的移除 / 改名等修改
            existing.update(title: title, items: items, startsNewSearch: didOpenResultsForCurrentSearch == false)
            // 搜索中结果持续刷新，只在本次搜索首次展示时前置窗口，避免反复抢占焦点
            if didOpenResultsForCurrentSearch == false {
                existing.showWindow(nil)
            }
            didOpenResultsForCurrentSearch = true
            latestResultsWindowController = existing
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

        // 闭包在控制器创建前构造，借助弱引用局部变量拿到「自己」所在的结果窗口
        weak var createdController: SearchResultsWindowController?
        let controller = SearchResultsWindowController(
            viewModel: viewModel,
            title: title,
            expandFoldersWhenShowingResults: settings.expandFoldersWhenShowingResults,
            refreshHandler: { [weak self] in
                self?.refreshSearch(for: createdController)
            },
            refreshAvailability: { [weak self] in
                // 查找窗口释放后重新搜索不可用
                self?.canRefreshSearch(for: createdController) ?? false
            }
        )
        createdController = controller
        controller.showWindow(nil)
        resultsWindowController = controller
        latestResultsWindowController = controller
        didOpenResultsForCurrentSearch = true
    }

    /// 结果页在搜索进行中（提前显示结果）打开或更新时标记为搜索中，搜索结束后由 handleStateTransition 更新
    private var searchStatusForResultsWindow: SearchResultsViewModel.SearchStatus {
        state.phase.isSearching ? .searching : .finished
    }

    /// 记录结果窗口当前展示的是哪次搜索
    private func bindCurrentSearch(to controller: SearchResultsWindowController) {
        guard let lastSearchRequest else {
            return
        }
        searchesByResultsWindow[ObjectIdentifier(controller)] = ResultsWindowSearch(
            request: lastSearchRequest,
            sessionSnapshot: lastSubmittedSessionSnapshot
        )
    }

    /// 结果窗口的「重新搜索」（⌘R）是否可用：查找窗口空闲且该窗口记录过搜索条件
    private func canRefreshSearch(for controller: SearchResultsWindowController?) -> Bool {
        guard state.phase.isSearching == false, let controller else {
            return false
        }
        return searchesByResultsWindow[ObjectIdentifier(controller)] != nil
    }

    /// 按结果窗口自己的条件重新搜索，结果回到发起重新搜索的这个窗口
    private func refreshSearch(for controller: SearchResultsWindowController?) {
        guard canRefreshSearch(for: controller),
              let controller,
              let search = searchesByResultsWindow[ObjectIdentifier(controller)] else {
            return
        }

        var sessionSnapshot = search.sessionSnapshot
        // 沿用结果窗口当前的显示方式，避免重新搜索后被重置为提交时的状态
        sessionSnapshot?.presentationState = controller.currentPresentationState
        lastSearchRequest = search.request
        lastSubmittedSessionSnapshot = sessionSnapshot
        didOpenResultsForCurrentSearch = false
        resultsWindowController = controller
        workflowController.start(request: search.request, preferences: settings.searchExecutionPreferences)
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
        resultsWindowController?.window === window || latestResultsWindowController?.window === window
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

    /// 不启动真实搜索，直接让表单进入「搜索中」状态
    func debugSimulateSearching() {
        workflowController.onStateChange?(.init(phase: .searching(scopeDescription: "Fixture", matchCount: 0)))
    }

    func debugSetLastSearchRequest(_ request: SearchRequest) {
        lastSearchRequest = request
    }

    var debugResultsWindowController: SearchResultsWindowController? {
        resultsWindowController
    }

    var debugLatestResultsWindowController: SearchResultsWindowController? {
        latestResultsWindowController
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

    var debugShowLastResultsButtonVisible: Bool {
        showLastResultsButton.isHidden == false
    }

    var debugShowLastResultsButtonTitle: String {
        showLastResultsButton.title
    }

    /// 布局后按钮、转圈指示器与主按钮的实际 frame（同一坐标系），用于校验按钮未被挤压
    func debugStatusBarFrames() -> (showResults: NSRect, activity: NSRect, primary: NSRect, fittingWidth: CGFloat) {
        view.layoutSubtreeIfNeeded()
        return (
            showLastResultsButton.frame,
            activityIndicator.frame,
            primaryButton.frame,
            showLastResultsButton.fittingSize.width
        )
    }

    func debugShowLastResults() {
        showLastResultsPressed()
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

/// 结果窗口对应的一次搜索：请求本身与提交时的会话快照（用于重新搜索后写入历史）
private struct ResultsWindowSearch {
    let request: SearchRequest
    let sessionSnapshot: SearchSessionSnapshot?
}

/// 拖放设置搜索范围的纯逻辑：拖入文件夹（或卷宗）直接作为范围，拖入文件取其所在文件夹。
/// 范围快照只支持单一根路径，拖入多项时取第一个文件 URL
enum SearchScopeDropResolver {
    static func folderURL(from urls: [URL], isFolder: (URL) -> Bool = SearchScopeDropResolver.isFolder) -> URL? {
        guard let url = urls.first(where: \.isFileURL)?.standardizedFileURL else {
            return nil
        }
        return isFolder(url) ? url : url.deletingLastPathComponent()
    }

    /// 文件夹与卷宗根目录视为文件夹；应用等包虽然是目录，但在访达中表现为文件，按文件处理
    static func isFolder(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else {
            return false
        }
        return values.isDirectory == true && values.isPackage != true
    }

    /// 从拖放剪贴板读取文件 URL
    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return (objects as? [URL]) ?? []
    }
}

/// 查找窗口的根视图：接收访达拖入的文件夹 / 文件来设置搜索范围，拖入时在内容区四周显示强调色边框
final class SearchFormDropView: NSView {
    /// 是否允许拖放（搜索中范围不可修改）
    var canAcceptDrop: () -> Bool = { true }
    /// 松手后处理拖入的 URL，返回是否接受
    var onDropURLs: (([URL]) -> Bool)?

    private let backgroundView = AppearanceAwareView()
    private let highlightView = SearchFormDropHighlightView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backgroundView.backgroundColorProvider = { _ in .windowBackgroundColor }
        addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        highlightView.isHidden = true
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 在所有控件添加完成后调用，让高亮边框位于最上层
    func installDropHighlight() {
        addSubview(highlightView)
        highlightView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(3)
        }
    }

    var isDropHighlighted: Bool {
        highlightView.isHidden == false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dragOperation(for: sender)
        setDropHighlighted(operation.isEmpty == false)
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dragOperation(for: sender)
        setDropHighlighted(operation.isEmpty == false)
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropHighlighted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setDropHighlighted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragOperation(for: sender).isEmpty == false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDropHighlighted(false)
        let urls = SearchScopeDropResolver.fileURLs(from: sender.draggingPasteboard)
        return onDropURLs?(urls) ?? false
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptDrop(),
              SearchScopeDropResolver.fileURLs(from: sender.draggingPasteboard).isEmpty == false else {
            return []
        }
        return .generic
    }

    func setDropHighlighted(_ highlighted: Bool) {
        highlightView.isHidden = highlighted == false
        if highlighted {
            highlightView.refreshBorderColor()
        }
    }
}

/// 拖放高亮边框：不参与点击命中，避免挡住下面的控件
private final class SearchFormDropHighlightView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.borderWidth = 3
        layer?.cornerRadius = 8
        refreshBorderColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBorderColor()
    }

    func refreshBorderColor() {
        layer?.borderColor = NSColor.controlAccentColor.fhResolvedCGColor(for: effectiveAppearance)
    }
}
