import AppKit

final class SearchResultsWindowController: NSWindowController {
    private let resultsViewController: SearchResultsViewController
    private let viewModel: SearchResultsViewModel
    private let refreshHandler: (() -> Void)?
    private var activationObserver: NSObjectProtocol?

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
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.window?.isVisible == true else {
                return
            }
            self.refreshHandler?()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
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
