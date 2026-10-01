import AppKit

final class SearchResultsWindowController: NSWindowController, NSMenuItemValidation {
    private let resultsViewController: SearchResultsViewController
    private let viewModel: SearchResultsViewModel
    private let refreshHandler: (() -> Void)?

    init(
        viewModel: SearchResultsViewModel,
        title: String,
        expandFoldersWhenShowingResults: Bool = false,
        refreshHandler: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.resultsViewController = SearchResultsViewController(
            viewModel: viewModel,
            expandsFoldersWhenShowingResults: expandFoldersWhenShowingResults
        )
        self.refreshHandler = refreshHandler
        let window = NSWindow(contentViewController: resultsViewController)
        window.setAccessibilityIdentifier("SearchResultsWindow")
        window.title = title
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 菜单「重新搜索」（⌘R）：按上次的条件重新执行搜索
    @objc func refreshSearchResults(_ sender: Any?) {
        refreshHandler?()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(refreshSearchResults(_:)) {
            return refreshHandler != nil
        }
        return true
    }

    var expandsFoldersWhenShowingResults: Bool {
        get { resultsViewController.expandsFoldersWhenShowingResults }
        set { resultsViewController.expandsFoldersWhenShowingResults = newValue }
    }

    func update(title: String, items: [SearchResultItem]) {
        window?.title = title
        viewModel.title = title
        viewModel.items = items
    }

    func apply(presentationState: ResultPresentationState) {
        viewModel.apply(presentationState: presentationState)
    }

    var currentPresentationState: ResultPresentationState {
        viewModel.presentationState
    }
}
