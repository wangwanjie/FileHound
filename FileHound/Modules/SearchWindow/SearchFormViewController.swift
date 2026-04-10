import AppKit
import SnapKit

@MainActor
final class SearchFormViewController: NSViewController {
    weak var windowLayoutDelegate: SearchWindowLayoutDelegate?

    private let scopePopup = NSPopUpButton()
    private let rulesViewController = SearchRulesViewController()
    private let statusLabel = NSTextField(labelWithString: "Items Found: 0")
    private let activityIndicator = NSProgressIndicator()
    private let primaryButton = NSButton(title: "Find", target: nil, action: nil)
    private let workflowController = SearchWorkflowController()
    private let scopeProvider = SearchScopeMenuProvider()
    private var scopeItems: [SearchScopeMenuItem] = []
    private var resultsWindowController: SearchResultsWindowController?
    private var lastSearchRequest: SearchRequest?
    private var lastConfirmedScopeIndex = 0
    private var rulesHeightConstraint: Constraint?

    private var state = SearchWindowState(phase: .idle(matchCount: 0)) {
        didSet { render(state) }
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleLabel = NSTextField(labelWithString: L10n.string("search_window.find_items"))
        let whereLabel = NSTextField(labelWithString: L10n.string("search_window.where"))

        scopePopup.setAccessibilityIdentifier("SearchScopePopup")
        scopePopup.setAccessibilityLabel("SearchScopePopup")
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
            self.rulesHeightConstraint = make.height.equalTo(130).constraint
        }
        statusLabel.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview().inset(20)
            make.top.equalTo(rulesViewController.view.snp.bottom).offset(16)
        }
        primaryButton.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(20)
            make.top.greaterThanOrEqualTo(rulesViewController.view.snp.bottom).offset(16)
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
        rulesViewController.onContentLayoutChange = { [weak self] contentHeight in
            self?.windowLayoutDelegate?.searchFormViewController(self, desiredRulesContentHeight: contentHeight)
        }

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureScopePopup()
        render(state)
        windowLayoutDelegate?.searchFormViewController(self, desiredRulesContentHeight: rulesViewController.preferredContentHeight)

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
        lastConfirmedScopeIndex = 0
    }

    @objc
    private func primaryButtonPressed() {
        switch state.phase {
        case .searching:
            workflowController.cancel()
            state = .init(phase: .editing(matchCount: 0))
        default:
            let scopeItem = selectedScopeItem()
            let request = SearchRequest(
                scopeDescription: scopeItem.scopeDescription,
                rootPath: scopeItem.representedPath ?? "/",
                rules: rulesViewController.currentSelections
            )
            lastSearchRequest = request
            workflowController.start(request: request)
        }
    }

    @objc
    private func scopeSelectionChanged() {
        let item = selectedScopeItem()
        guard item.kind == .folderPicker else {
            lastConfirmedScopeIndex = scopePopup.indexOfSelectedItem
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            let title = "inside \(url.lastPathComponent)"
            let updated = SearchScopeMenuItem(
                title: title,
                representedPath: url.path,
                scopeDescription: url.lastPathComponent,
                kind: .folderPicker
            )
            let index = scopePopup.indexOfSelectedItem
            scopeItems[index] = updated
            scopePopup.item(at: index)?.title = title
            lastConfirmedScopeIndex = index
            return
        }

        scopePopup.selectItem(at: lastConfirmedScopeIndex)
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

        guard items.isEmpty == false else {
            return
        }

        let viewModel = SearchResultsViewModel()
        viewModel.title = title
        viewModel.items = items
        viewModel.mode = .grid

        let controller = SearchResultsWindowController(
            viewModel: viewModel,
            title: title,
            refreshHandler: { [weak self] in
                self?.refreshLastSearchIfNeeded()
            }
        )
        controller.showWindow(nil)
        resultsWindowController = controller
    }

    private func refreshLastSearchIfNeeded() {
        guard state.phase.isSearching == false,
              let lastSearchRequest,
              resultsWindowController?.window?.isVisible == true else {
            return
        }

        workflowController.start(request: lastSearchRequest)
    }

    func applyRuleAreaLayout(height: CGFloat, shouldScroll: Bool) {
        rulesHeightConstraint?.update(offset: height)
        rulesViewController.setScrollingEnabled(shouldScroll)
        view.layoutSubtreeIfNeeded()
    }

    var preferredRulesContentHeight: CGFloat {
        rulesViewController.preferredContentHeight
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
