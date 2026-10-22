import AppKit
import Combine
import CoreServices
import QuickLookUI
import SnapKit
import UniformTypeIdentifiers

final class SearchResultsViewController: NSViewController, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let viewModel: SearchResultsViewModel
    var expandsFoldersWhenShowingResults: Bool {
        didSet {
            treeController.expandsFoldersOnReload = expandsFoldersWhenShowingResults
        }
    }
    private let gridController = ResultsCollectionViewController()
    private let tableController = ResultsTableViewController()
    private let treeController = ResultsOutlineViewController()
    private let toolbarView = ResultsToolbarView()
    private let containerView = NSView()
    private let statusBarView = ResultsStatusBarView()
    private let emptyStateLabel = NSTextField(labelWithString: L10n.string("results.empty"))
    private lazy var actionController = ResultActionController(confirmationPresenter: { [weak self] request in
        self?.confirm(request: request) ?? false
    })
    private var menuHandlers: [MenuActionHandler] = []
    private var quickLookURLs: [URL] = []
    private let trashedItemsWatcher = DirectoryChangeWatcher()
    private var activationObservers: [NSObjectProtocol] = []
    private var displayedItemCount = 0
    /// 隐藏中的视图模式：数据变化时只刷新当前可见视图，切换过去时再刷新
    private var staleModes: Set<SearchResultsViewModel.Mode> = []
    /// 切换视图模式期间忽略各视图的选中回调，切换完成后由视图模型的选中推给新视图
    private var isSwitchingMode = false
    private let localizationPublisher: AnyPublisher<AppLanguage, Never>
    private var cancellables: Set<AnyCancellable> = []
    /// 测试用：没有窗口时用于替代模态弹窗的导出 / 确认结果
    var confirmationOverride: ((ResultConfirmationRequest) -> Bool)?
    private(set) var localizationReloadCount = 0

    init(
        viewModel: SearchResultsViewModel,
        expandsFoldersWhenShowingResults: Bool = false,
        localizationPublisher: AnyPublisher<AppLanguage, Never> = LocalizationController.shared.publisher
    ) {
        self.viewModel = viewModel
        self.expandsFoldersWhenShowingResults = expandsFoldersWhenShowingResults
        self.localizationPublisher = localizationPublisher
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        activationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func loadView() {
        let rootView = AppearanceAwareView()
        rootView.setAccessibilityIdentifier("SearchResultsRootView")
        rootView.setAccessibilityElement(true)
        rootView.backgroundColorProvider = { appearance in
            .fhWindowSurface(for: appearance)
        }

        addChild(gridController)
        addChild(tableController)
        addChild(treeController)
        containerView.addSubview(gridController.view)
        containerView.addSubview(tableController.view)
        containerView.addSubview(treeController.view)
        containerView.addSubview(emptyStateLabel)

        emptyStateLabel.alignment = .center
        emptyStateLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.isHidden = true

        toolbarView.gridButton.target = self
        toolbarView.gridButton.action = #selector(showGridMode)
        toolbarView.tableButton.target = self
        toolbarView.tableButton.action = #selector(showTableMode)
        toolbarView.treeButton.target = self
        toolbarView.treeButton.action = #selector(showTreeMode)
        toolbarView.filterField.target = self
        toolbarView.filterField.action = #selector(filterChanged)
        toolbarView.previewSlider.target = self
        toolbarView.previewSlider.action = #selector(previewSizeChanged)
        toolbarView.sortByPopup.target = self
        toolbarView.sortByPopup.action = #selector(sortByChanged)
        toolbarView.invisiblesButton.target = self
        toolbarView.invisiblesButton.action = #selector(toggleInvisibles)
        toolbarView.packageButton.target = self
        toolbarView.packageButton.action = #selector(togglePackages)
        toolbarView.trashedButton.target = self
        toolbarView.trashedButton.action = #selector(toggleTrashed)
        toolbarView.exportButton.target = self
        toolbarView.exportButton.action = #selector(exportSearchResults(_:))

        rootView.addSubview(toolbarView)
        rootView.addSubview(containerView)
        rootView.addSubview(statusBarView)

        toolbarView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
        }
        containerView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.top.equalTo(toolbarView.snp.bottom)
            make.bottom.equalTo(statusBarView.snp.top)
        }
        statusBarView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(28)
        }
        gridController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        tableController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        treeController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        emptyStateLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        treeController.expandsFoldersOnReload = expandsFoldersWhenShowingResults
        observeItemsPutBackFromTrash()

        // 只采纳当前可见视图的选中回调，隐藏视图的旧选中不能覆盖视图模型
        gridController.onSelectionSetChange = { [weak self] items in
            self?.updateSelection(items, from: .grid)
        }
        tableController.onSelectionSetChange = { [weak self] items in
            self?.updateSelection(items, from: .table)
        }
        treeController.onSelectionSetChange = { [weak self] items in
            self?.updateSelection(items, from: .tree)
        }
        gridController.contextMenuProvider = { [weak self] items in
            self?.makeContextMenu(for: items)
        }
        tableController.contextMenuProvider = { [weak self] items in
            self?.makeContextMenu(for: items)
        }
        treeController.contextMenuProvider = { [weak self] items in
            self?.makeContextMenu(for: items)
        }
        gridController.onOpenItems = { [weak self] items in
            self?.open(items: items, applicationURL: nil)
        }
        tableController.onOpenItems = { [weak self] items in
            self?.open(items: items, applicationURL: nil)
        }
        treeController.onOpenItems = { [weak self] items in
            self?.open(items: items, applicationURL: nil)
        }
        gridController.onQuickLookRequest = { [weak self] items in
            self?.showQuickLook(items: items)
        }
        tableController.onSortChange = { [weak self] field, order in
            self?.applySort(field: field, order: order)
        }
        tableController.onQuickLookRequest = { [weak self] items in
            self?.showQuickLook(items: items)
        }
        treeController.onSortChange = { [weak self] field, order in
            self?.applySort(field: field, order: order)
        }
        treeController.onQuickLookRequest = { [weak self] items in
            self?.showQuickLook(items: items)
        }

        viewModel.onModeChange = { [weak self] mode in
            self?.render(mode: mode)
        }
        viewModel.onSelectionChange = { [weak self] item in
            self?.statusBarView.updateSelectedItem(item)
        }
        viewModel.onItemsChange = { [weak self] items in
            self?.refreshVisibleView(with: items)
        }
        viewModel.onSearchStatusChange = { [weak self] status in
            self?.renderEmptyState()
            self?.statusBarView.updateSearchStatus(status)
        }
        viewModel.onSortChange = { [weak self] field, order in
            self?.toolbarView.selectSortField(field)
            self?.tableController.applySort(field: field, order: order)
            self?.treeController.applySort(field: field, order: order)
        }
        viewModel.onPreviewSizeChange = { [weak self] previewSize in
            self?.toolbarView.previewSlider.doubleValue = previewSize
            self?.applyPreviewSize(CGFloat(previewSize))
        }

        viewModel.onFilterChange = { [weak self] filterText in
            self?.syncToolbarFilterState(filterText: filterText)
        }

        syncToolbarFilterState(filterText: viewModel.filterText)
        toolbarView.previewSlider.doubleValue = viewModel.previewSize
        applyPreviewSize(CGFloat(viewModel.previewSize))
        toolbarView.selectSortField(viewModel.sortField)
        tableController.applySort(field: viewModel.sortField, order: viewModel.sortOrder)
        treeController.applySort(field: viewModel.sortField, order: viewModel.sortOrder)
        staleModes = [.grid, .table, .tree]
        render(mode: viewModel.mode)
        refreshVisibleView(with: viewModel.projectedItems)
        statusBarView.updateSearchStatus(viewModel.searchStatus)
        statusBarView.updateSelectedItem(viewModel.selectedItem)

        // 应用内切换语言时自行刷新结果窗口文案；CurrentValueSubject 订阅时会立即发送当前语言，跳过这一次
        localizationPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadLocalizedStrings()
            }
            .store(in: &cancellables)
    }

    /// 只刷新当前可见的视图，其余视图标记为过期，切换过去时再刷新
    private func refreshVisibleView(with items: [SearchResultItem]) {
        let mode = viewModel.mode
        resultsController(for: mode).update(items: items)
        staleModes = Set([SearchResultsViewModel.Mode.grid, .table, .tree]).subtracting([mode])
        displayedItemCount = items.count
        renderEmptyState()
        statusBarView.updateMatchCount(items.count)
        toolbarView.exportButton.isEnabled = items.isEmpty == false
    }

    private func resultsController(for mode: SearchResultsViewModel.Mode) -> ResultsViewUpdating {
        switch mode {
        case .grid:
            return gridController
        case .table:
            return tableController
        case .tree:
            return treeController
        }
    }

    /// 视图模型的过滤条件可能被外部修改（如恢复展示状态），同步工具栏控件
    private func syncToolbarFilterState(filterText: String) {
        toolbarView.invisiblesButton.state = viewModel.showInvisibleItems ? .on : .off
        toolbarView.packageButton.state = viewModel.showPackageContents ? .on : .off
        toolbarView.trashedButton.state = viewModel.showTrashedItems ? .on : .off
        if toolbarView.filterField.stringValue != filterText {
            toolbarView.filterField.stringValue = filterText
        }
    }

    /// 应用内切换语言后刷新结果窗口的全部文案
    func reloadLocalizedStrings() {
        localizationReloadCount += 1
        toolbarView.reloadLocalizedStrings()
        toolbarView.selectSortField(viewModel.sortField)
        tableController.reloadLocalizedStrings()
        treeController.reloadColumnTitles()
        emptyStateLabel.stringValue = L10n.string("results.empty")
        statusBarView.reloadLocalizedStrings()
        // 树视图的合成文件夹节点种类文案随语言变化：可见时立即重建，否则切换过去时再重建
        if viewModel.mode == .tree {
            treeController.update(items: viewModel.projectedItems)
        } else {
            staleModes.insert(.tree)
        }
    }

    @objc
    private func showGridMode() {
        viewModel.mode = .grid
    }

    @objc
    private func showTableMode() {
        viewModel.mode = .table
    }

    @objc
    private func showTreeMode() {
        viewModel.mode = .tree
    }

    @objc
    private func filterChanged() {
        viewModel.filterText = toolbarView.filterField.stringValue
    }

    @objc
    private func previewSizeChanged() {
        viewModel.previewSize = toolbarView.previewSlider.doubleValue
    }

    @objc
    private func sortByChanged() {
        // 只改变排序字段，保留当前的升序 / 降序
        applySort(field: toolbarView.selectedSortField, order: viewModel.sortOrder)
    }

    @objc
    private func toggleInvisibles() {
        viewModel.showInvisibleItems = toolbarView.invisiblesButton.state == .on
    }

    @objc
    private func togglePackages() {
        viewModel.showPackageContents = toolbarView.packageButton.state == .on
    }

    @objc
    private func toggleTrashed() {
        viewModel.showTrashedItems = toolbarView.trashedButton.state == .on
    }

    private func render(mode: SearchResultsViewModel.Mode) {
        isSwitchingMode = true
        // 目标视图的数据已过期时先刷新，再把视图模型的选中推给它
        if staleModes.contains(mode) {
            resultsController(for: mode).update(items: viewModel.projectedItems)
            staleModes.remove(mode)
        }
        resultsController(for: mode).select(ids: viewModel.selectedIDs)
        isSwitchingMode = false

        gridController.view.isHidden = mode != .grid
        tableController.view.isHidden = mode != .table
        treeController.view.isHidden = mode != .tree
        toolbarView.apply(mode: mode)
    }

    private func renderEmptyState() {
        // 搜索仍在进行时不显示“没有结果”，结果可能马上就会到来
        emptyStateLabel.isHidden = displayedItemCount > 0 || viewModel.searchStatus == .searching
    }

    private func updateSelection(_ items: [SearchResultItem], from mode: SearchResultsViewModel.Mode) {
        guard isSwitchingMode == false, mode == viewModel.mode else {
            return
        }

        viewModel.selectedIDs = Set(items.map(\.id))
        if viewModel.selectedItem != items.first {
            viewModel.selectedItem = items.first
        }
    }

    private func applyPreviewSize(_ previewSize: CGFloat) {
        gridController.updatePreviewSize(previewSize)
    }

    private func applySort(field: SearchResultsViewModel.SortField, order: SearchResultsViewModel.SortOrder) {
        viewModel.sortField = field
        viewModel.sortOrder = order
    }

    private func makeContextMenu(for items: [SearchResultItem]) -> NSMenu? {
        guard items.isEmpty == false else {
            return nil
        }

        menuHandlers.removeAll()
        let menu = NSMenu(title: "ResultsContextMenu")
        // 关闭自动启用：否则 NSMenu 会按 target 能否响应 action 把禁用项重新启用，isEnabled 设置无效
        menu.autoenablesItems = false
        // 树视图补出的上级文件夹不是匹配结果，只允许打开、显示、拷贝路径等非破坏性操作
        let state = actionController.menuState(for: items) { [viewModel] item in
            viewModel.containsItem(id: item.id)
        }

        menu.addItem(makeMenuItem(title: openMenuTitle(for: items)) { [weak self] in
            self?.open(items: items, applicationURL: nil)
        })

        let openWithItem = NSMenuItem(title: L10n.string("results.menu.open_with"), action: nil, keyEquivalent: "")
        openWithItem.submenu = makeOpenWithMenu(for: items)
        menu.addItem(openWithItem)

        menu.addItem(makeMenuItem(title: L10n.string("results.menu.reveal_in_finder")) { [weak self] in
            self?.revealInFinder(items: items)
        })
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: L10n.string("results.menu.move_to_trash"), isEnabled: state.canMoveToTrash) { [weak self] in
            self?.moveToTrash(items: items)
        })
        menu.addItem(makeMenuItem(title: L10n.string("results.menu.delete_immediately"), isEnabled: state.canMoveToTrash) { [weak self] in
            self?.deleteImmediately(items: items)
        })
        menu.addItem(.separator())

        let copyPathItem = NSMenuItem(title: L10n.string("results.menu.copy_path"), action: nil, keyEquivalent: "")
        copyPathItem.submenu = makeCopyPathMenu(for: items)
        menu.addItem(copyPathItem)

        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: L10n.string("results.menu.get_info")) { [weak self] in
            self?.showInfo(items: items)
        })
        menu.addItem(makeMenuItem(title: L10n.string("results.menu.rename"), isEnabled: state.canRename) { [weak self] in
            self?.rename(item: items.first)
        })
        menu.addItem(makeMenuItem(title: L10n.string("results.menu.create_alias")) { [weak self] in
            self?.createAlias(items: items)
        })
        menu.addItem(makeMenuItem(title: L10n.string("results.menu.quick_look")) { [weak self] in
            self?.showQuickLook(items: items)
        })

        let labelItem = NSMenuItem(title: L10n.string("results.menu.set_label"), action: nil, keyEquivalent: "")
        labelItem.submenu = makeLabelMenu(for: items)
        labelItem.isEnabled = state.canModifyAttributes
        menu.addItem(labelItem)

        let shouldShowAsVisible = items.allSatisfy { self.isItemHidden($0) }
        menu.addItem(makeMenuItem(
            title: L10n.string(shouldShowAsVisible ? "results.menu.make_visible" : "results.menu.make_invisible"),
            isEnabled: state.canModifyAttributes
        ) { [weak self] in
            self?.setHidden(shouldHide: !shouldShowAsVisible, items: items)
        })
        menu.addItem(makeMenuItem(title: L10n.string("results.menu.unlock"), isEnabled: state.canModifyAttributes) { [weak self] in
            self?.unlock(items: items)
        })
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: L10n.string("results.menu.remove_from_results"), isEnabled: state.canRemoveFromResults) { [weak self] in
            guard let self else {
                return
            }
            self.actionController.removeFromResults(items: items, viewModel: self.viewModel)
        })
        menu.addItem(.separator())
        // 导出的是当前视图中的全部结果，不只是选中项
        menu.addItem(makeMenuItem(title: L10n.string("results.export.menu_title"), isEnabled: viewModel.projectedItems.isEmpty == false) { [weak self] in
            self?.exportSearchResults(nil)
        })

        return menu
    }

    private func openMenuTitle(for items: [SearchResultItem]) -> String {
        guard items.count == 1,
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: items[0].path)) else {
            return L10n.string("results.menu.open")
        }

        let appName = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        return L10n.format("results.menu.open_with_app", appName)
    }

    private func makeOpenWithMenu(for items: [SearchResultItem]) -> NSMenu {
        let menu = NSMenu(title: L10n.string("results.menu.open_with"))
        let apps = availableApplicationURLs(for: items)
        guard apps.isEmpty == false else {
            let item = NSMenuItem(title: L10n.string("results.menu.no_compatible_apps"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }

        for appURL in apps {
            let appName = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
            menu.addItem(makeMenuItem(title: appName) { [weak self] in
                self?.open(items: items, applicationURL: appURL)
            })
        }
        return menu
    }

    private func makeCopyPathMenu(for items: [SearchResultItem]) -> NSMenu {
        let menu = NSMenu(title: L10n.string("results.menu.copy_path"))
        menu.addItem(makeMenuItem(title: L10n.string("results.menu.posix_path")) {
            let value = items.map(\.path).joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        })
        menu.addItem(makeMenuItem(title: L10n.string("results.menu.file_url")) {
            let value = items.map { URL(fileURLWithPath: $0.path).absoluteString }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        })
        return menu
    }

    private func makeLabelMenu(for items: [SearchResultItem]) -> NSMenu {
        let menu = NSMenu(title: L10n.string("results.menu.set_label"))
        let labels: [(String, Int)] = [
            (L10n.string("results.label.none"), 0),
            (L10n.string("results.label.gray"), 1),
            (L10n.string("results.label.green"), 2),
            (L10n.string("results.label.purple"), 3),
            (L10n.string("results.label.blue"), 4),
            (L10n.string("results.label.yellow"), 5),
            (L10n.string("results.label.red"), 6),
            (L10n.string("results.label.orange"), 7)
        ]

        for (title, index) in labels {
            menu.addItem(makeMenuItem(title: title) { [weak self] in
                self?.setLabel(index: index, items: items)
            })
        }
        return menu
    }

    private func makeMenuItem(title: String, isEnabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let handler = MenuActionHandler(action: action)
        menuHandlers.append(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuActionHandler.invoke), keyEquivalent: "")
        item.target = handler
        item.isEnabled = isEnabled
        return item
    }

    private func open(items: [SearchResultItem], applicationURL: URL?) {
        let urls = items.map { URL(fileURLWithPath: $0.path) }
        if let applicationURL {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration) { _, _ in }
            return
        }

        urls.forEach { NSWorkspace.shared.open($0) }
    }

    private func revealInFinder(items: [SearchResultItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map { URL(fileURLWithPath: $0.path) })
    }

    private func moveToTrash(items: [SearchResultItem]) {
        do {
            try actionController.handleMoveToTrash(items: items, viewModel: viewModel)
        } catch {
            presentErrorAlert(error)
        }
        updateTrashedItemsWatcher()
    }

    /// 在访达中「放回原处」后让结果重新出现：监听原位置所在目录，并在窗口/应用重新激活时补查一次
    private func observeItemsPutBackFromTrash() {
        trashedItemsWatcher.onChange = { [weak self] in
            self?.restoreItemsPutBackFromTrash()
        }
        let center = NotificationCenter.default
        activationObservers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.restoreItemsPutBackFromTrash()
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self, notification.object as? NSWindow === self.view.window else { return }
                self.restoreItemsPutBackFromTrash()
            }
        ]
    }

    private func restoreItemsPutBackFromTrash() {
        guard viewModel.trashedEntries.isEmpty == false else {
            return
        }

        let restored = viewModel.restoreItemsPutBackFromTrash()
        if restored.isEmpty == false {
            viewModel.replaceItems(restored.compactMap { ResultItemRefresher.refreshedItem(from: $0, atPath: $0.path) })
        }
        updateTrashedItemsWatcher()
    }

    private func updateTrashedItemsWatcher() {
        trashedItemsWatcher.watch(directories: Set(viewModel.trashedEntries.map { URL(fileURLWithPath: $0.item.path).deletingLastPathComponent().path }))
    }

    private func deleteImmediately(items: [SearchResultItem]) {
        do {
            try actionController.handleDeleteImmediately(items: items, viewModel: viewModel)
        } catch {
            presentErrorAlert(error)
        }
    }

    private func rename(item: SearchResultItem?) {
        guard let item, viewModel.containsItem(id: item.id) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.string("results.rename.title")
        alert.informativeText = item.displayName
        alert.addButton(withTitle: L10n.string("results.rename.confirm"))
        alert.addButton(withTitle: L10n.string("common.cancel"))
        let field = NSTextField(string: item.displayName)
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try actionController.handleRename(item: item, newName: field.stringValue, viewModel: viewModel)
            } catch {
                presentErrorAlert(error)
            }
        }
    }

    private func createAlias(items: [SearchResultItem]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            for item in items {
                _ = try actionController.fileService.createAlias(for: URL(fileURLWithPath: item.path), in: destination)
            }
        } catch {
            presentErrorAlert(error)
        }
    }

    private func showQuickLook(items: [SearchResultItem]) {
        quickLookURLs = items.map { URL(fileURLWithPath: $0.path) }
        view.window?.makeFirstResponder(self)
        QLPreviewPanel.shared().reloadData()
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
    }

    private func setHidden(shouldHide: Bool, items: [SearchResultItem]) {
        applyAttributeChange(to: items) { [actionController] url in
            try actionController.fileService.setHidden(shouldHide, for: url)
        }
    }

    private func unlock(items: [SearchResultItem]) {
        applyAttributeChange(to: items) { [actionController] url in
            try actionController.fileService.setLocked(false, for: url)
        }
    }

    /// 逐项修改文件属性并刷新结果；与设置标签一致，失败时弹出第一个错误，成功的项照常刷新
    private func applyAttributeChange(to items: [SearchResultItem], change: (URL) throws -> URL) {
        // 合成的上级文件夹节点不是匹配结果，不允许修改
        let items = items.filter { viewModel.containsItem(id: $0.id) }
        var failure: Error?
        let updatedItems = items.compactMap { item -> SearchResultItem? in
            do {
                let url = try change(URL(fileURLWithPath: item.path))
                return ResultItemRefresher.refreshedItem(from: item, atPath: url.path)
            } catch {
                failure = failure ?? error
                return nil
            }
        }
        viewModel.replaceItems(updatedItems)
        if let failure {
            presentErrorAlert(failure)
        }
    }

    private func showInfo(items: [SearchResultItem]) {
        runFinderScript(commandBody: ["activate"] + items.map { item in
            #"open information window of (POSIX file "\#(escapedForAppleScript(item.path))" as alias)"#
        })
    }

    private func setLabel(index: Int, items: [SearchResultItem]) {
        applyAttributeChange(to: items) { [actionController] url in
            try actionController.fileService.setLabel(index, for: url)
        }
    }

    private func runFinderScript(commandBody: [String]) {
        let body = commandBody.joined(separator: "\n")
        let source = """
        tell application "Finder"
        \(body)
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? error.description
            let code = error[NSAppleScript.errorNumber] as? Int ?? 1
            presentErrorAlert(NSError(domain: "FinderScript", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
        }
    }

    private func availableApplicationURLs(for items: [SearchResultItem]) -> [URL] {
        let itemURLs = items.map { URL(fileURLWithPath: $0.path) }
        guard let first = itemURLs.first else {
            return []
        }

        var available = Set(applicationURLs(for: first).map(\.path))
        for url in itemURLs.dropFirst() {
            available.formIntersection(applicationURLs(for: url).map(\.path))
        }

        return available.map { URL(fileURLWithPath: $0) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func applicationURLs(for url: URL) -> [URL] {
        if #available(macOS 12.0, *) {
            return NSWorkspace.shared.urlsForApplications(toOpen: url)
        }

        let unmanaged = LSCopyApplicationURLsForURL(url as CFURL, LSRolesMask.all)
        return unmanaged?.takeRetainedValue() as? [URL] ?? []
    }

    private func isItemHidden(_ item: SearchResultItem) -> Bool {
        let values = try? URL(fileURLWithPath: item.path).resourceValues(forKeys: [.isHiddenKey])
        return values?.isHidden ?? item.isInvisible
    }

    private func presentErrorAlert(_ error: Error) {
        let alert = NSAlert(error: error as NSError)
        alert.runModal()
    }

    private func escapedForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func confirm(request: ResultConfirmationRequest) -> Bool {
        if let confirmationOverride {
            return confirmationOverride(request)
        }

        switch request {
        case .deleteImmediately:
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.string("results.delete.title")
            // 单个项目写出名称与路径，多个项目写出数量，避免误删
            alert.informativeText = request.informativeText
            alert.addButton(withTitle: L10n.string("results.delete.confirm"))
            alert.addButton(withTitle: L10n.string("common.cancel"))
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    /// 菜单「文件 > 导出结果…」（⇧⌘E，经响应链到达）、工具栏导出按钮与右键菜单共用：
    /// 导出当前视图投影后（经过滤、排序、隐藏项设置）的结果
    @objc
    func exportSearchResults(_ sender: Any?) {
        let items = viewModel.projectedItems
        guard items.isEmpty == false else {
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = L10n.string("results.export.title")
        panel.nameFieldStringValue = ResultExportFormatter.suggestedFileName(
            title: viewModel.title,
            fallback: L10n.string("results.export.default_name"),
            format: .csv
        )
        panel.allowedContentTypes = [ResultExportFormat.csv.contentType]

        // 保存面板附加格式选择：CSV / 纯文本，切换时同步修改扩展名
        let formatLabel = NSTextField(labelWithString: L10n.string("results.export.format"))
        let formatPopup = NSPopUpButton()
        formatPopup.addItems(withTitles: ResultExportFormat.allCases.map(\.localizedTitle))
        let formatHandler = MenuActionHandler { [weak panel, weak formatPopup] in
            guard let panel, let formatPopup else {
                return
            }
            let format = ResultExportFormat.allCases[max(formatPopup.indexOfSelectedItem, 0)]
            panel.allowedContentTypes = [format.contentType]
            let baseName = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = baseName + "." + format.fileExtension
        }
        formatPopup.target = formatHandler
        formatPopup.action = #selector(MenuActionHandler.invoke)
        let accessory = NSStackView(views: [formatLabel, formatPopup])
        accessory.orientation = .horizontal
        accessory.spacing = 8
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = accessory

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            // 持有格式切换处理对象直到面板关闭
            _ = formatHandler
            guard response == .OK, let url = panel.url else {
                return
            }
            let format = ResultExportFormat.allCases[max(formatPopup.indexOfSelectedItem, 0)]
            do {
                try ResultExportFormatter.data(for: items, format: format).write(to: url, options: .atomic)
            } catch {
                self?.presentErrorAlert(error)
            }
        }

        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    @objc
    func openSelectedResults(_ sender: Any?) {
        let items = viewModel.selectedItems
        guard items.isEmpty == false else { return }
        open(items: items, applicationURL: nil)
    }

    @objc
    func moveSelectedResultsToTrash(_ sender: Any?) {
        let items = viewModel.selectedItems
        guard items.isEmpty == false else { return }
        moveToTrash(items: items)
    }

    /// ⌘C：把选中结果作为文件 URL 写入剪贴板，同时附带以换行分隔的路径文本
    @objc
    func copy(_ sender: Any?) {
        writeSelectedItems(to: .general)
    }

    @discardableResult
    func writeSelectedItems(to pasteboard: NSPasteboard) -> Bool {
        let selectedURLs = viewModel.selectedItems.map { URL(fileURLWithPath: $0.path) }
        guard selectedURLs.isEmpty == false else {
            return false
        }

        pasteboard.clearContents()
        pasteboard.writeObjects(selectedURLs as [NSURL])
        pasteboard.setString(selectedURLs.map(\.path).joined(separator: "\n"), forType: .string)
        return true
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        let selectedURLs = viewModel.selectedItems.map { URL(fileURLWithPath: $0.path) }
        guard selectedURLs.isEmpty == false else {
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }

        if sendType == nil || sendType == .fileURL || sendType == .string {
            return self
        }

        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc
    func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let selectedURLs = viewModel.selectedItems.map { URL(fileURLWithPath: $0.path) }
        guard selectedURLs.isEmpty == false else {
            return false
        }

        pasteboard.clearContents()
        if types.contains(.fileURL) {
            return pasteboard.writeObjects(selectedURLs as [NSURL])
        }

        if types.contains(.string) {
            pasteboard.setString(selectedURLs.map(\.path).joined(separator: "\n"), forType: .string)
            return true
        }

        return false
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        quickLookURLs[index] as NSURL
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

#if DEBUG
extension SearchResultsViewController {
    var debugShowsEmptyState: Bool {
        emptyStateLabel.isHidden == false
    }

    var debugStatusText: String {
        statusBarView.debugCountText
    }

    var debugShowsSearchActivity: Bool {
        statusBarView.searchStatus == .searching
    }

    var debugSelectedMode: SearchResultsViewModel.Mode? {
        if toolbarView.gridButton.state == .on {
            return .grid
        }
        if toolbarView.tableButton.state == .on {
            return .table
        }
        if toolbarView.treeButton.state == .on {
            return .tree
        }
        return nil
    }

    var debugShowsPreviewSlider: Bool {
        toolbarView.previewSlider.isHidden == false
    }

    var debugShowsSortPopup: Bool {
        toolbarView.sortByPopup.isHidden == false
    }

    var debugGridItemSize: NSSize {
        gridController.debugItemSize
    }

    func debugSetPreviewSize(_ value: Double) {
        toolbarView.previewSlider.doubleValue = value
        previewSizeChanged()
    }

    func debugGridTitleAlignmentOffset(for item: SearchResultItem, previewSize: CGFloat) -> CGFloat {
        gridController.debugTitleAlignmentOffset(for: item, previewSize: previewSize)
    }

    func debugGridTitleParagraphAlignment(for item: SearchResultItem, previewSize: CGFloat) -> NSTextAlignment {
        gridController.debugTitleParagraphAlignment(for: item, previewSize: previewSize)
    }

    var debugGridTitleMaximumNumberOfLines: Int {
        gridController.debugTitleMaximumNumberOfLines
    }

    var debugGridTitleLineBreakMode: NSLineBreakMode {
        gridController.debugTitleLineBreakMode
    }

    var debugMatchCountValue: Int {
        statusBarView.matchCountValue
    }

    var debugSelectedPathComponents: [String] {
        statusBarView.displayedPathComponents
    }

    var debugToolbarTooltips: [String] {
        [
            toolbarView.gridButton.toolTip,
            toolbarView.tableButton.toolTip,
            toolbarView.treeButton.toolTip,
            toolbarView.invisiblesButton.toolTip,
            toolbarView.packageButton.toolTip,
            toolbarView.trashedButton.toolTip
        ].compactMap { $0 }
    }

    func debugToggleInvisibles() {
        toolbarView.invisiblesButton.performClick(nil)
    }

    func debugTogglePackages() {
        toolbarView.packageButton.performClick(nil)
    }

    func debugToggleTrashed() {
        toolbarView.trashedButton.performClick(nil)
    }

    var debugSortTitles: [String] {
        toolbarView.sortByPopup.itemTitles
    }

    func debugRootBackgroundHex(for appearanceName: NSAppearance.Name) -> String {
        let appearance = NSAppearance(named: appearanceName)
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)!
        return NSColor.fhWindowSurface(for: appearance).fhResolvedHex(for: appearanceName)
    }

    func debugToolbarBackgroundHex(for appearanceName: NSAppearance.Name) -> String {
        toolbarView.debugBackgroundHex(for: appearanceName)
    }

    func debugStatusBackgroundHex(for appearanceName: NSAppearance.Name) -> String {
        statusBarView.debugBackgroundHex(for: appearanceName)
    }

    var debugGridController: ResultsCollectionViewController {
        gridController
    }

    var debugTableController: ResultsTableViewController {
        tableController
    }

    var debugTreeController: ResultsOutlineViewController {
        treeController
    }

    var debugPreviewLabelText: String {
        toolbarView.debugPreviewLabelText
    }

    var debugEmptyStateText: String {
        emptyStateLabel.stringValue
    }

    var debugExportButtonEnabled: Bool {
        toolbarView.exportButton.isEnabled
    }

    var debugToolbarAccessibilityLabels: [String: String] {
        let buttons: [NSButton] = [
            toolbarView.gridButton,
            toolbarView.tableButton,
            toolbarView.treeButton,
            toolbarView.invisiblesButton,
            toolbarView.packageButton,
            toolbarView.trashedButton
        ]
        var labels: [String: String] = [:]
        for button in buttons {
            labels[button.accessibilityIdentifier()] = button.accessibilityLabel() ?? ""
        }
        return labels
    }

    func debugContextMenu(for items: [SearchResultItem]) -> NSMenu? {
        makeContextMenu(for: items)
    }

    func debugSelectSortFieldFromPopup(_ field: SearchResultsViewModel.SortField) {
        toolbarView.selectSortField(field)
        sortByChanged()
    }

    func debugDeleteImmediately(items: [SearchResultItem]) {
        deleteImmediately(items: items)
    }

    /// 切换根视图外观后读取根视图、工具栏、状态栏 layer 上实际设置的背景色
    func debugLayerBackgroundColors(appearanceName: NSAppearance.Name) -> (root: CGColor?, toolbar: CGColor?, status: CGColor?) {
        view.appearance = NSAppearance(named: appearanceName)
        return (view.layer?.backgroundColor, toolbarView.debugLayerBackgroundColor, statusBarView.debugLayerBackgroundColor)
    }
}
#endif

/// 三种结果视图共有的刷新与选中同步接口
private protocol ResultsViewUpdating: AnyObject {
    func update(items: [SearchResultItem])
    func select(ids: Set<SearchResultItem.ID>)
}

extension ResultsCollectionViewController: ResultsViewUpdating {}
extension ResultsTableViewController: ResultsViewUpdating {}
extension ResultsOutlineViewController: ResultsViewUpdating {}

private final class MenuActionHandler: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc
    func invoke() {
        action()
    }
}

private final class ResultsStatusBarView: NSView {
    private let pathStackView = NSStackView()
    private let countLabel = NSTextField(labelWithString: "")
    private let activityIndicator = NSProgressIndicator()
    private var buttonHandlers: [MenuActionHandler] = []

    private(set) var displayedPathComponents: [String] = []
    private(set) var matchCountValue = 0
    private(set) var searchStatus: SearchResultsViewModel.SearchStatus = .finished

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        let borderLayer = CALayer()
        layer?.addSublayer(borderLayer)

        pathStackView.orientation = .horizontal
        pathStackView.alignment = .centerY
        pathStackView.spacing = 4
        pathStackView.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.setAccessibilityIdentifier("SearchResultsStatusLabel")

        activityIndicator.style = .spinning
        activityIndicator.controlSize = .small
        activityIndicator.isDisplayedWhenStopped = false
        activityIndicator.setAccessibilityIdentifier("SearchResultsActivityIndicator")

        addSubview(pathStackView)
        addSubview(activityIndicator)
        addSubview(countLabel)

        pathStackView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.trailing.lessThanOrEqualTo(activityIndicator.snp.leading).offset(-12)
        }
        activityIndicator.snp.makeConstraints { make in
            make.trailing.equalTo(countLabel.snp.leading).offset(-6)
            make.centerY.equalToSuperview()
            make.size.equalTo(14)
        }
        countLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
        }

        applyAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    override func layout() {
        super.layout()
        guard let borderLayer = layer?.sublayers?.first else {
            return
        }
        borderLayer.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }

    func updateMatchCount(_ count: Int) {
        matchCountValue = count
        renderCountLabel()
    }

    func updateSearchStatus(_ status: SearchResultsViewModel.SearchStatus) {
        searchStatus = status
        if status == .searching {
            activityIndicator.startAnimation(nil)
        } else {
            activityIndicator.stopAnimation(nil)
        }
        renderCountLabel()
    }

    var debugCountText: String {
        countLabel.stringValue
    }

    func reloadLocalizedStrings() {
        renderCountLabel()
    }

    private func renderCountLabel() {
        let key: String
        switch searchStatus {
        case .searching:
            key = "results.status.searching"
        case .stopped:
            key = "results.status.stopped"
        case .finished:
            key = "results.status.matched"
        }
        countLabel.stringValue = L10n.format(key, matchCountValue)
        countLabel.setAccessibilityLabel(countLabel.stringValue)
    }

    func updateSelectedItem(_ item: SearchResultItem?) {
        buttonHandlers.removeAll()
        displayedPathComponents = []
        pathStackView.arrangedSubviews.forEach {
            pathStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard let item else {
            pathStackView.isHidden = true
            return
        }

        pathStackView.isHidden = false
        let segments = breadcrumbSegments(for: item.path)
        displayedPathComponents = segments.map(\.title)

        for (index, segment) in segments.enumerated() {
            let button = ResultsPathComponentButton(title: segment.title)
            let handler = MenuActionHandler { [path = segment.path] in
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            button.target = handler
            button.action = #selector(MenuActionHandler.invoke)
            buttonHandlers.append(handler)
            pathStackView.addArrangedSubview(button)

            if index < segments.count - 1 {
                let separator = NSTextField(labelWithString: "/")
                separator.font = .systemFont(ofSize: 11, weight: .medium)
                separator.textColor = .tertiaryLabelColor
                pathStackView.addArrangedSubview(separator)
            }
        }
    }

    private func breadcrumbSegments(for path: String) -> [(title: String, path: String)] {
        let components = URL(fileURLWithPath: path).pathComponents.filter { $0 != "/" }
        var currentPath = ""
        return components.map { component in
            currentPath += "/\(component)"
            return (title: component, path: currentPath)
        }
    }

    private func applyAppearance(resolvedAgainst appearance: NSAppearance? = nil) {
        let resolvedAppearance = appearance ?? effectiveAppearance
        layer?.backgroundColor = NSColor.fhPanelSurface(for: resolvedAppearance, alpha: 0.96).fhResolvedCGColor(for: resolvedAppearance)
        layer?.sublayers?.first?.backgroundColor = NSColor.fhHairline(for: resolvedAppearance).fhResolvedCGColor(for: resolvedAppearance)
    }

    #if DEBUG
    func debugBackgroundHex(for appearanceName: NSAppearance.Name) -> String {
        let appearance = NSAppearance(named: appearanceName)
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)!
        return NSColor.fhPanelSurface(for: appearance, alpha: 0.96).fhResolvedHex(for: appearanceName)
    }

    var debugLayerBackgroundColor: CGColor? {
        layer?.backgroundColor
    }
    #endif
}

private final class ResultsPathComponentButton: NSButton {
    private let fadeView = ResultsFadeView()
    private var isHovered = false
    private var trackingAreaReference: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .inline
        imagePosition = .noImage
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 4
        toolTip = title
        cell?.lineBreakMode = .byTruncatingTail
        addSubview(fadeView)
        fadeView.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview()
            make.width.equalTo(18)
        }
        snp.makeConstraints { make in
            make.width.lessThanOrEqualTo(120)
        }
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let trackingAreaReference = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaReference)
        self.trackingAreaReference = trackingAreaReference
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        super.mouseExited(with: event)
    }

    override func layout() {
        super.layout()
        fadeView.isHidden = intrinsicContentSize.width <= bounds.width || isHovered
    }

    private func updateAppearance() {
        let color: NSColor = isHovered ? .controlAccentColor : .secondaryLabelColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: isHovered ? .semibold : .regular),
                .foregroundColor: color
            ]
        )
        layer?.backgroundColor = isHovered ? NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
    }
}

private final class ResultsFadeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let gradientLayer: CAGradientLayer
        if let existing = layer as? CAGradientLayer {
            gradientLayer = existing
        } else {
            gradientLayer = CAGradientLayer()
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            self.layer = gradientLayer
        }
        gradientLayer.colors = [
            NSColor.fhPanelSurface(for: effectiveAppearance, alpha: 0).fhResolvedCGColor(for: effectiveAppearance),
            NSColor.fhPanelSurface(for: effectiveAppearance).fhResolvedCGColor(for: effectiveAppearance)
        ]
        gradientLayer.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}

struct SearchResultNameHighlighter {
    static func attributedTitle(
        for item: SearchResultItem,
        baseColor: NSColor,
        font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    ) -> NSAttributedString {
        let title = item.displayName
        let attributed = NSMutableAttributedString(
            string: title,
            attributes: [
                .foregroundColor: baseColor,
                .font: font
            ]
        )

        for range in highlightRanges(for: item, title: title) {
            attributed.addAttributes(
                [
                    .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.28),
                    .foregroundColor: baseColor
                ],
                range: range
            )
        }

        return attributed
    }

    private static func highlightRanges(for item: SearchResultItem, title: String) -> [NSRange] {
        guard let kind = item.highlightKind,
              let query = item.highlightQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
              query.isEmpty == false else {
            return []
        }

        let searchTerms = query
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { $0.isEmpty == false }
        guard searchTerms.isEmpty == false else {
            return []
        }

        let candidateRange: Range<String.Index>
        switch kind {
        case .name:
            candidateRange = title.startIndex..<title.endIndex
        case .extensionName:
            guard let dotIndex = title.lastIndex(of: ".") else {
                return []
            }
            candidateRange = dotIndex..<title.endIndex
        }

        return searchTerms.compactMap { term in
            let normalized = kind == .extensionName ? term.trimmingCharacters(in: CharacterSet(charactersIn: ".")) : term
            guard normalized.isEmpty == false,
                  let range = title.range(of: normalized, options: [.caseInsensitive, .diacriticInsensitive], range: candidateRange) else {
                return nil
            }

            // NSAttributedString 按 UTF-16 偏移计算，不能用 Character 距离（emoji、组合字符会错位）
            return NSRange(range, in: title)
        }
    }
}

extension SearchResultsViewController: NSUserInterfaceValidations {
    /// 工具栏按钮等非菜单界面元素的验证，与菜单验证保持一致
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(exportSearchResults(_:)):
            return viewModel.projectedItems.isEmpty == false
        default:
            return true
        }
    }
}

extension SearchResultsViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(moveSelectedResultsToTrash(_:)):
            // 过滤框等文本输入获得焦点时 ⌘⌫ 留给文本编辑，避免误删文件
            return viewModel.selectedItems.isEmpty == false && (view.window?.firstResponder is NSText) == false
        case #selector(openSelectedResults(_:)), #selector(copy(_:)):
            return viewModel.selectedItems.isEmpty == false
        case #selector(exportSearchResults(_:)):
            return viewModel.projectedItems.isEmpty == false
        default:
            return true
        }
    }
}
