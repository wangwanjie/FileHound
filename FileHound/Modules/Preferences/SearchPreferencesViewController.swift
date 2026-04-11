import AppKit
import SnapKit

final class SearchPreferencesViewController: NSViewController {
    private let settings: AppSettings
    private let specialFoldersStore: SpecialFoldersStore
    private let expandFoldersButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let showResultsEarlyButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let includeSpotlightButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let specialFoldersButton = NSButton(title: "", target: nil, action: nil)
    private var specialFoldersWindowController: SpecialFoldersWindowController?

    init(
        settings: AppSettings = .shared,
        specialFoldersStore: SpecialFoldersStore = .shared
    ) {
        self.settings = settings
        self.specialFoldersStore = specialFoldersStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.search.title"),
            subtitle: L10n.string("preferences.search.subtitle")
        )

        expandFoldersButton.title = L10n.string("preferences.search.expand_folders")
        expandFoldersButton.state = settings.expandFoldersWhenShowingResults ? .on : .off
        expandFoldersButton.setAccessibilityIdentifier("SearchPreferenceExpandFoldersButton")
        expandFoldersButton.target = self
        expandFoldersButton.action = #selector(expandFoldersChanged)
        showResultsEarlyButton.title = L10n.string("preferences.search.show_results_early")
        showResultsEarlyButton.state = settings.showResultsEarly ? .on : .off
        showResultsEarlyButton.setAccessibilityIdentifier("SearchPreferenceShowResultsEarlyButton")
        showResultsEarlyButton.target = self
        showResultsEarlyButton.action = #selector(showResultsEarlyChanged)
        includeSpotlightButton.title = L10n.string("preferences.search.include_spotlight")
        includeSpotlightButton.state = settings.includeSpotlightResults ? .on : .off
        includeSpotlightButton.setAccessibilityIdentifier("SearchPreferenceIncludeSpotlightButton")
        includeSpotlightButton.target = self
        includeSpotlightButton.action = #selector(includeSpotlightChanged)
        specialFoldersButton.title = L10n.string("preferences.search.special_folders")
        specialFoldersButton.setAccessibilityIdentifier("SearchPreferenceSpecialFoldersButton")
        specialFoldersButton.target = self
        specialFoldersButton.action = #selector(openSpecialFolders)

        let stack = NSStackView(views: [
            expandFoldersButton,
            showResultsEarlyButton,
            includeSpotlightButton,
            specialFoldersButton
        ])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .leading
        rootView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(rootView.contentGuide)
        }

        view = rootView
    }

    @objc
    private func expandFoldersChanged() {
        settings.expandFoldersWhenShowingResults = expandFoldersButton.state == .on
    }

    @objc
    private func showResultsEarlyChanged() {
        settings.showResultsEarly = showResultsEarlyButton.state == .on
    }

    @objc
    private func includeSpotlightChanged() {
        settings.includeSpotlightResults = includeSpotlightButton.state == .on
    }

    @objc
    private func openSpecialFolders() {
        let controller = specialFoldersWindowController ?? SpecialFoldersWindowController(store: specialFoldersStore)
        specialFoldersWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

final class SpecialFoldersWindowController: NSWindowController {
    convenience init(store: SpecialFoldersStore = .shared) {
        let rootViewController = SpecialFoldersEditorViewController(store: store)
        let window = NSWindow(contentViewController: rootViewController)
        window.setContentSize(NSSize(width: 680, height: 360))
        window.title = L10n.string("preferences.search.special_folders.window_title")
        window.center()
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        self.init(window: window)
    }
}

final class SpecialFoldersEditorViewController: NSViewController {
    private let store: SpecialFoldersStore
    private var configuration: SpecialFoldersConfiguration
    private let stackView = NSStackView()
    private let addButton = NSButton(title: "", target: nil, action: nil)
    private let emptyStateLabel = NSTextField(labelWithString: "")

    init(store: SpecialFoldersStore = .shared) {
        self.store = store
        self.configuration = store.load()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = PreferencesSectionView(
            title: L10n.string("preferences.search.special_folders.title"),
            subtitle: L10n.string("preferences.search.special_folders.subtitle")
        )

        stackView.orientation = .vertical
        stackView.spacing = 10
        stackView.alignment = .leading
        addButton.title = L10n.string("preferences.search.special_folders.add")
        emptyStateLabel.stringValue = L10n.string("preferences.search.special_folders.empty")
        emptyStateLabel.textColor = .secondaryLabelColor
        addButton.target = self
        addButton.action = #selector(addFolder)

        rootView.addSubview(stackView)
        rootView.addSubview(addButton)
        stackView.snp.makeConstraints { make in
            make.leading.trailing.top.equalTo(rootView.contentGuide)
        }
        addButton.snp.makeConstraints { make in
            make.top.equalTo(stackView.snp.bottom).offset(14)
            make.leading.bottom.equalTo(rootView.contentGuide)
        }

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadRows()
    }

    @objc
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.string("preferences.search.special_folders.add_prompt")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        addRule(path: url.path, disposition: .exclude)
    }

    private func addRule(path: String, disposition: SpecialFolderDisposition) {
        configuration.rules.append(SpecialFolderRule(path: path, disposition: disposition))
        persistAndReload()
    }

    private func updateRule(id: UUID, disposition: SpecialFolderDisposition) {
        guard let index = configuration.rules.firstIndex(where: { $0.id == id }) else {
            return
        }

        configuration.rules[index].disposition = disposition
        persistAndReload()
    }

    private func removeRule(id: UUID) {
        configuration.rules.removeAll { $0.id == id }
        persistAndReload()
    }

    private func persistAndReload() {
        try? store.save(configuration)
        reloadRows()
    }

    private func reloadRows() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard configuration.rules.isEmpty == false else {
            stackView.addArrangedSubview(emptyStateLabel)
            return
        }

        for rule in configuration.rules {
            let rowView = SpecialFolderRuleRowView(rule: rule)
            rowView.onDispositionChange = { [weak self] disposition in
                self?.updateRule(id: rule.id, disposition: disposition)
            }
            rowView.onRemove = { [weak self] in
                self?.removeRule(id: rule.id)
            }
            stackView.addArrangedSubview(rowView)
        }
    }
}

#if DEBUG
extension SpecialFoldersEditorViewController {
    func debugAddRule(path: String, disposition: SpecialFolderDisposition) {
        addRule(path: path, disposition: disposition)
    }

    func debugSetDisposition(_ disposition: SpecialFolderDisposition, at index: Int) {
        guard configuration.rules.indices.contains(index) else {
            return
        }
        updateRule(id: configuration.rules[index].id, disposition: disposition)
    }

    func debugRemoveRule(at index: Int) {
        guard configuration.rules.indices.contains(index) else {
            return
        }
        removeRule(id: configuration.rules[index].id)
    }

    var debugRules: [SpecialFolderRule] {
        configuration.rules
    }
}
#endif

private final class SpecialFolderRuleRowView: NSView {
    private let dispositionPopup = NSPopUpButton()
    private let removeButton = NSButton(title: "", target: nil, action: nil)
    var onDispositionChange: ((SpecialFolderDisposition) -> Void)?
    var onRemove: (() -> Void)?

    init(rule: SpecialFolderRule) {
        super.init(frame: .zero)

        let pathLabel = NSTextField(labelWithString: rule.path)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dispositionPopup.addItems(withTitles: SpecialFolderDisposition.menuTitles)
        dispositionPopup.selectItem(at: SpecialFolderDisposition.menuOrder.firstIndex(of: rule.disposition) ?? 1)
        dispositionPopup.target = self
        dispositionPopup.action = #selector(dispositionChanged)
        removeButton.title = L10n.string("preferences.search.special_folders.remove")
        removeButton.target = self
        removeButton.action = #selector(removeTapped)

        [pathLabel, dispositionPopup, removeButton].forEach(addSubview)
        pathLabel.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
        }
        dispositionPopup.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(pathLabel.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.trailing.equalTo(removeButton.snp.leading).offset(-10)
            make.width.equalTo(140)
        }
        removeButton.snp.makeConstraints { make in
            make.trailing.centerY.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func dispositionChanged() {
        let index = max(dispositionPopup.indexOfSelectedItem, 0)
        onDispositionChange?(SpecialFolderDisposition.menuOrder[index])
    }

    @objc
    private func removeTapped() {
        onRemove?()
    }
}

private extension SpecialFolderDisposition {
    static let menuOrder: [SpecialFolderDisposition] = [.include, .exclude, .slowSearch]

    static var menuTitles: [String] {
        menuOrder.map(\.displayName)
    }

    var displayName: String {
        switch self {
        case .include:
            return L10n.string("preferences.search.special_folders.disposition.include")
        case .exclude:
            return L10n.string("preferences.search.special_folders.disposition.exclude")
        case .slowSearch:
            return L10n.string("preferences.search.special_folders.disposition.slow_search")
        }
    }
}
