import AppKit

final class SearchResultsWindowController: NSWindowController, NSMenuItemValidation {
    /// 窗口打开期间由此持有：所属查找窗口关闭并被释放后，结果窗口仍可继续使用，直到用户关闭它
    private static var openControllers: [ObjectIdentifier: SearchResultsWindowController] = [:]

    private let resultsViewController: SearchResultsViewController
    private let viewModel: SearchResultsViewModel
    private let refreshHandler: (() -> Void)?
    /// 「重新搜索」当前是否可用（例如所属查找窗口已释放或正在搜索时不可用）；nil 表示只要有 refreshHandler 即可用
    private let refreshAvailability: (() -> Bool)?

    init(
        viewModel: SearchResultsViewModel,
        title: String,
        expandFoldersWhenShowingResults: Bool = false,
        refreshHandler: (() -> Void)? = nil,
        refreshAvailability: (() -> Bool)? = nil
    ) {
        self.viewModel = viewModel
        self.resultsViewController = SearchResultsViewController(
            viewModel: viewModel,
            expandsFoldersWhenShowingResults: expandFoldersWhenShowingResults
        )
        self.refreshHandler = refreshHandler
        self.refreshAvailability = refreshAvailability
        let window = NSWindow(contentViewController: resultsViewController)
        window.setAccessibilityIdentifier("SearchResultsWindow")
        window.title = title
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        Self.openControllers[ObjectIdentifier(self)] = self
    }

    @objc
    private func windowWillClose(_ notification: Notification) {
        Self.openControllers[ObjectIdentifier(self)] = nil
    }

    /// 菜单「重新搜索」（⌘R）：按上次的条件重新执行搜索
    @objc func refreshSearchResults(_ sender: Any?) {
        refreshHandler?()
    }

    @objc func showResultsAsIcons(_ sender: Any?) {
        viewModel.mode = .grid
    }

    @objc func showResultsAsList(_ sender: Any?) {
        viewModel.mode = .table
    }

    @objc func showResultsAsTree(_ sender: Any?) {
        viewModel.mode = .tree
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(refreshSearchResults(_:)):
            return refreshHandler != nil && (refreshAvailability?() ?? true)
        case #selector(showResultsAsIcons(_:)):
            menuItem.state = viewModel.mode == .grid ? .on : .off
        case #selector(showResultsAsList(_:)):
            menuItem.state = viewModel.mode == .table ? .on : .off
        case #selector(showResultsAsTree(_:)):
            menuItem.state = viewModel.mode == .tree ? .on : .off
        default:
            break
        }
        return true
    }

    var expandsFoldersWhenShowingResults: Bool {
        get { resultsViewController.expandsFoldersWhenShowingResults }
        set { resultsViewController.expandsFoldersWhenShowingResults = newValue }
    }

    /// 更新结果。startsNewSearch 为 true 表示新一次搜索的首批结果：清空用户在旧结果上的移除 / 改名记录与废纸篓跟踪；
    /// 为 false 表示同一次搜索的流式进度：合并时保留用户在搜索过程中做的移除、移到废纸篓、改名等修改
    func update(title: String, items: [SearchResultItem], startsNewSearch: Bool = true) {
        window?.title = title
        viewModel.title = title
        if startsNewSearch {
            viewModel.beginNewSearch(with: items)
        } else {
            viewModel.mergeSearchProgress(items)
        }
    }

    var searchStatus: SearchResultsViewModel.SearchStatus {
        get { viewModel.searchStatus }
        set { viewModel.searchStatus = newValue }
    }

    func apply(presentationState: ResultPresentationState) {
        viewModel.apply(presentationState: presentationState)
    }

    var currentPresentationState: ResultPresentationState {
        viewModel.presentationState
    }
}

#if DEBUG
extension SearchResultsWindowController {
    /// 测试清理：关闭所有仍由静态表持有的结果窗口
    static func debugCloseAllOpenWindows() {
        for controller in openControllers.values {
            controller.window?.close()
        }
        openControllers.removeAll()
    }

    static var debugOpenControllerCount: Int {
        openControllers.count
    }
}
#endif
