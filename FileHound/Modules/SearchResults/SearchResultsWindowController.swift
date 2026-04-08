import AppKit

final class SearchResultsWindowController: NSWindowController {
    private let resultsViewController: SearchResultsViewController

    init(viewModel: SearchResultsViewModel, title: String) {
        self.resultsViewController = SearchResultsViewController(viewModel: viewModel)
        let window = NSWindow(contentViewController: resultsViewController)
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
}
