import AppKit
import SnapKit

@MainActor
final class SearchFormViewController: NSViewController {
    private let scopePopup = NSPopUpButton()
    private let rulesViewController = SearchRulesViewController()
    private let statusLabel = NSTextField(labelWithString: "Items Found: 0")
    private let activityIndicator = NSProgressIndicator()
    private let primaryButton = NSButton(title: "Find", target: nil, action: nil)
    private let workflowController = SearchWorkflowController()
    private let scopeProvider = SearchScopeMenuProvider()
    private var scopeItems: [SearchScopeMenuItem] = []
    private var resultsWindowController: SearchResultsWindowController?

    private var state = SearchWindowState(phase: .idle(matchCount: 0)) {
        didSet { render(state) }
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleLabel = NSTextField(labelWithString: "Find Items")
        let whereLabel = NSTextField(labelWithString: "where")

        scopePopup.setAccessibilityIdentifier("SearchScopePopup")
        scopePopup.setAccessibilityLabel("SearchScopePopup")
        statusLabel.setAccessibilityIdentifier("SearchStatusLabel")
        primaryButton.setAccessibilityIdentifier("PrimarySearchButton")
        activityIndicator.setAccessibilityIdentifier("SearchActivityIndicator")
        activityIndicator.setAccessibilityLabel("SearchActivityIndicator")

        primaryButton.target = self
        primaryButton.action = #selector(primaryButtonPressed)
        primaryButton.keyEquivalent = "\r"

        activityIndicator.style = .spinning
        activityIndicator.controlSize = .small
        activityIndicator.isDisplayedWhenStopped = false

        addChild(rulesViewController)
        [titleLabel, scopePopup, whereLabel, rulesViewController.view, statusLabel, activityIndicator, primaryButton].forEach(rootView.addSubview)

        titleLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(20)
        }
        scopePopup.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.trailing).offset(16)
            make.centerY.equalTo(titleLabel)
            make.width.equalTo(320)
        }
        whereLabel.snp.makeConstraints { make in
            make.leading.equalTo(scopePopup.snp.trailing).offset(16)
            make.centerY.equalTo(titleLabel)
        }
        rulesViewController.view.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.top.equalTo(titleLabel.snp.bottom).offset(18)
            make.bottom.equalTo(statusLabel.snp.top).offset(-16)
        }
        statusLabel.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview().inset(20)
        }
        primaryButton.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(20)
            make.width.equalTo(170)
            make.height.equalTo(44)
        }
        activityIndicator.snp.makeConstraints { make in
            make.trailing.equalTo(primaryButton.snp.leading).offset(-12)
            make.centerY.equalTo(primaryButton)
        }

        workflowController.onStateChange = { [weak self] state in
            self?.state = state
        }
        workflowController.onResults = { [weak self] title, items in
            self?.openResultsWindow(title: title, items: items)
        }

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureScopePopup()
        render(state)

        if ProcessInfo.processInfo.arguments.contains("--fixture-results") {
            let items = workflowController.fixtureItems()
            openResultsWindow(title: "Name contains report", items: items)
            state = .init(phase: .idle(matchCount: items.count))
        }
    }

    private func configureScopePopup() {
        scopePopup.removeAllItems()
        scopeItems = scopeProvider.sections().flatMap { $0.items }
        scopePopup.addItems(withTitles: scopeItems.map(\.title))
        scopePopup.selectItem(at: 0)
    }

    @objc
    private func primaryButtonPressed() {
        switch state.phase {
        case .searching:
            workflowController.cancel()
            state = .init(phase: .editing(matchCount: 0))
        default:
            let selection = rulesViewController.currentSelection
            let scopeItem = selectedScopeItem()
            workflowController.start(
                request: SearchRequest(
                    scopeDescription: scopeItem.scopeDescription,
                    rootPath: scopeItem.representedPath ?? "/",
                    query: selection
                )
            )
        }
    }

    private func selectedScopeItem() -> SearchScopeMenuItem {
        let index = max(scopePopup.indexOfSelectedItem, 0)
        return scopeItems[index]
    }

    private func render(_ state: SearchWindowState) {
        statusLabel.stringValue = state.statusText
        statusLabel.setAccessibilityLabel(state.statusText)
        primaryButton.title = state.primaryActionTitle
        primaryButton.setAccessibilityLabel(state.primaryActionTitle)
        scopePopup.isEnabled = state.isEditingEnabled
        rulesViewController.setEnabled(state.isEditingEnabled)

        if state.showsActivityIndicator {
            activityIndicator.startAnimation(nil)
        } else {
            activityIndicator.stopAnimation(nil)
        }
    }

    private func openResultsWindow(title: String, items: [SearchResultItem]) {
        if let existing = resultsWindowController {
            existing.update(title: title, items: items)
            existing.showWindow(nil)
            return
        }

        let viewModel = SearchResultsViewModel()
        viewModel.title = title
        viewModel.items = items
        viewModel.mode = .table

        let controller = SearchResultsWindowController(viewModel: viewModel, title: title)
        controller.showWindow(nil)
        resultsWindowController = controller
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

    var debugStatusText: String {
        statusLabel.stringValue
    }
}
#endif
