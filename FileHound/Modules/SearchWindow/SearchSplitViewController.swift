import AppKit
import SnapKit

final class SearchSplitViewController: NSViewController {
    private let scopePopup = NSPopUpButton()
    private let ruleContainerView = NSView()
    private let rulesStackView = NSStackView()
    private let explanationLabel = NSTextField(labelWithString: "")
    private let findButton = NSButton(title: "Find", target: nil, action: nil)
    private var ruleViews: [SearchRuleEditorView] = []
    private var resultsWindowController: SearchResultsWindowController?
    private let resultViewModel = SearchResultsViewModel()

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(calibratedWhite: 0.23, alpha: 1).cgColor

        let titleLabel = NSTextField(labelWithString: "Find Items")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .white

        scopePopup.addItems(withTitles: ["on startup volume", "in home folder"])
        scopePopup.selectItem(at: 0)

        let whereLabel = NSTextField(labelWithString: "where")
        whereLabel.font = .systemFont(ofSize: 22, weight: .medium)
        whereLabel.textColor = .white

        let sentenceStack = NSStackView(views: [titleLabel, scopePopup, whereLabel])
        sentenceStack.orientation = .horizontal
        sentenceStack.spacing = 16
        sentenceStack.alignment = .centerY

        ruleContainerView.wantsLayer = true
        ruleContainerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.27, alpha: 1).cgColor
        ruleContainerView.layer?.cornerRadius = 10
        ruleContainerView.layer?.borderColor = NSColor(calibratedWhite: 0.35, alpha: 1).cgColor
        ruleContainerView.layer?.borderWidth = 1

        rulesStackView.orientation = .vertical
        rulesStackView.spacing = 10
        rulesStackView.alignment = .leading

        explanationLabel.font = .systemFont(ofSize: 13, weight: .regular)
        explanationLabel.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        explanationLabel.maximumNumberOfLines = 2

        findButton.bezelStyle = .rounded
        findButton.keyEquivalent = "\r"
        findButton.target = self
        findButton.action = #selector(findClicked)

        rootView.addSubview(sentenceStack)
        rootView.addSubview(ruleContainerView)
        ruleContainerView.addSubview(rulesStackView)
        rootView.addSubview(explanationLabel)
        rootView.addSubview(findButton)

        sentenceStack.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(20)
            make.trailing.lessThanOrEqualToSuperview().inset(20)
        }
        ruleContainerView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.top.equalTo(sentenceStack.snp.bottom).offset(18)
        }
        rulesStackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
        }
        explanationLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.trailing.equalTo(findButton.snp.leading).offset(-20)
            make.top.equalTo(ruleContainerView.snp.bottom).offset(12)
            make.bottom.equalToSuperview().inset(20)
        }
        findButton.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(20)
            make.width.equalTo(160)
            make.height.equalTo(40)
        }

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addRule()

        if ProcessInfo.processInfo.arguments.contains("--fixture-results") {
            let items = [
                SearchResultItem(
                    path: "/tmp/report.txt",
                    matchReason: "内容命中",
                    previewSnippet: "demo",
                    kind: "Text Document",
                    modifiedText: "2026/04/08 17:00",
                    sizeText: "4 KB"
                )
            ]
            openResultsWindow(title: "Name contains report", items: items)
        }
    }

    @objc
    private func addRule() {
        let ruleView = SearchRuleEditorView()
        ruleView.onAdd = { [weak self] in self?.addRule() }
        ruleView.onRemove = { [weak self, weak ruleView] in
            guard let self, let ruleView else { return }
            self.removeRule(ruleView)
        }
        ruleView.onChange = { [weak self] in
            self?.updateExplanation()
        }
        ruleViews.append(ruleView)
        rulesStackView.addArrangedSubview(ruleView)
        updateRuleButtons()
        updateExplanation()
    }

    private func removeRule(_ ruleView: SearchRuleEditorView) {
        guard ruleViews.count > 1 else { return }
        ruleViews.removeAll { $0 === ruleView }
        rulesStackView.removeArrangedSubview(ruleView)
        ruleView.removeFromSuperview()
        updateRuleButtons()
        updateExplanation()
    }

    private func updateRuleButtons() {
        for (index, ruleView) in ruleViews.enumerated() {
            ruleView.showsAddButton = index == 0
            ruleView.showsRemoveButton = ruleViews.count > 1
        }
    }

    private func updateExplanation() {
        explanationLabel.stringValue = ruleViews.first?.currentRule.explanationText ?? "Enter a search term."
    }

    @objc
    private func findClicked() {
        Task {
            let items = await performSearch()
            await MainActor.run {
                let title = resultWindowTitle()
                openResultsWindow(title: title, items: items)
            }
        }
    }

    private func resultWindowTitle() -> String {
        guard let rule = ruleViews.first?.currentRule else {
            return "Results"
        }
        return "\(rule.field.displayName) \(rule.operatorOption.displayName) \(rule.value)"
    }

    private func searchRootPath() -> String {
        scopePopup.indexOfSelectedItem == 0 ? "/" : NSHomeDirectory()
    }

    private func performSearch() async -> [SearchResultItem] {
        let rootPath = searchRootPath()
        let activeRules = ruleViews.map(\.currentRule).filter { $0.value.isEmpty == false }
        let includeHidden = activeRules.contains { $0.field == .invisibleItems } || ProcessInfo.processInfo.arguments.contains("--uitesting")

        let plan = SearchPlan(
            rootPaths: [rootPath],
            rootGroup: .all([]),
            excludedPathFragments: [],
            providerKind: .local,
            shouldScanContents: activeRules.contains { $0.field == .textContent }
        )

        let walker = DirectoryWalker()
        let provider = LocalFilesystemProvider()
        let metadataEvaluator = MetadataEvaluator()
        let contentMatcher = ContentMatcher()

        do {
            let entries = try walker.walk(plan: plan, includeHiddenFiles: includeHidden)
            let filtered = try entries.filter { entry in
                try activeRules.allSatisfy { rule in
                    try matches(rule: rule, entry: entry, metadataEvaluator: metadataEvaluator, provider: provider, contentMatcher: contentMatcher)
                }
            }

            return try filtered.map { entry in
                let attributes = try provider.attributesOfItem(atPath: entry.path)
                return SearchResultItem(
                    path: entry.path,
                    matchReason: activeRules.first?.matchReason ?? "名称命中",
                    previewSnippet: activeRules.first?.field == .textContent ? activeRules.first?.value : nil,
                    kind: displayKind(for: entry, attributes: attributes),
                    modifiedText: displayModifiedDate(attributes: attributes),
                    sizeText: displaySize(attributes: attributes),
                    isInvisible: entry.isHidden,
                    isPackage: URL(fileURLWithPath: entry.path).pathExtension == "app"
                )
            }
        } catch {
            return []
        }
    }

    private func matches(
        rule: SearchRuleEditorView.RuleState,
        entry: DirectoryEntry,
        metadataEvaluator: MetadataEvaluator,
        provider: LocalFilesystemProvider,
        contentMatcher: ContentMatcher
    ) throws -> Bool {
        switch rule.field {
        case .name, .tag:
            return matchText(rule: rule, text: entry.lastPathComponent, fallbackContains: { metadataEvaluator.matchesName(entry, fragment: $0) })
        case .path:
            return matchText(rule: rule, text: entry.path, fallbackContains: { metadataEvaluator.matchesPath(entry, fragment: $0) })
        case .extension:
            return matchText(rule: rule, text: URL(fileURLWithPath: entry.path).pathExtension, fallbackContains: { _ in false })
        case .textContent:
            guard entry.isDirectory == false else { return false }
            let queryRule: QueryRule = rule.operatorOption.isRegex ? .contentMatchesRegex(rule.value) : .contentContains(rule.value)
            let data = try provider.contentsOfFile(atPath: entry.path)
            return try contentMatcher.matches(data: data, query: queryRule)
        case .kind:
            return matchText(rule: rule, text: displayKind(for: entry, attributes: try provider.attributesOfItem(atPath: entry.path)), fallbackContains: { _ in false })
        default:
            return true
        }
    }

    private func matchText(
        rule: SearchRuleEditorView.RuleState,
        text: String,
        fallbackContains: (String) -> Bool
    ) -> Bool {
        let value = rule.value
        switch rule.operatorOption {
        case .contains, .containsPhrase:
            return fallbackContains(value) || text.localizedCaseInsensitiveContains(value)
        case .beginsWith:
            return text.lowercased().hasPrefix(value.lowercased())
        case .endsWith:
            return text.lowercased().hasSuffix(value.lowercased())
        case .is:
            return text.caseInsensitiveCompare(value) == .orderedSame
        case .doesNotContain:
            return text.localizedCaseInsensitiveContains(value) == false
        case .matchesPattern, .matchesRegex:
            return text.range(of: value, options: .regularExpression) != nil
        case .doesNotMatchRegex:
            return text.range(of: value, options: .regularExpression) == nil
        default:
            return text.localizedCaseInsensitiveContains(value)
        }
    }

    private func displayKind(for entry: DirectoryEntry, attributes: [FileAttributeKey: Any]) -> String {
        if entry.isDirectory {
            return "Folder"
        }
        let ext = URL(fileURLWithPath: entry.path).pathExtension
        if ext.isEmpty {
            return "Document"
        }
        return ext.uppercased() + " Document"
    }

    private func displayModifiedDate(attributes: [FileAttributeKey: Any]) -> String {
        guard let date = attributes[.modificationDate] as? Date else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d, h:mm:ss a"
        return formatter.string(from: date)
    }

    private func displaySize(attributes: [FileAttributeKey: Any]) -> String {
        guard let size = attributes[.size] as? NSNumber else {
            return ""
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size.int64Value)
    }

    private func openResultsWindow(title: String, items: [SearchResultItem]) {
        resultViewModel.title = title
        resultViewModel.items = items
        resultViewModel.mode = .table

        if let windowController = resultsWindowController {
            windowController.window?.title = title
            windowController.showWindow(nil)
            return
        }

        let controller = SearchResultsWindowController(viewModel: resultViewModel, title: title)
        controller.showWindow(nil)
        resultsWindowController = controller
    }
}

private final class SearchRuleEditorView: NSView {
    struct RuleState {
        let field: SearchFieldOption
        let operatorOption: SearchOperatorOption
        let value: String

        var explanationText: String {
            switch field {
            case .name, .tag:
                return "Enter one or more text fragments that all have to appear in a file name, separated by spaces."
            case .textContent:
                return "Searches file contents for the text or pattern you entered."
            default:
                return "Refine the search by adjusting the field, operator, and value."
            }
        }

        var matchReason: String {
            switch field {
            case .textContent:
                return "内容命中"
            case .path:
                return "路径命中"
            default:
                return "名称命中"
            }
        }
    }

    let addButton = NSButton(title: "⊕", target: nil, action: nil)
    let removeButton = NSButton(title: "⊖", target: nil, action: nil)
    let fieldPopup = NSPopUpButton()
    let operatorPopup = NSPopUpButton()
    let valueField = NSTextField()

    var onAdd: (() -> Void)?
    var onRemove: (() -> Void)?
    var onChange: (() -> Void)?

    var showsAddButton: Bool = true {
        didSet { addButton.isHidden = showsAddButton == false }
    }

    var showsRemoveButton: Bool = true {
        didSet { removeButton.isHidden = showsRemoveButton == false }
    }

    var currentRule: RuleState {
        RuleState(
            field: SearchFieldOption.allCases[fieldPopup.indexOfSelectedItem],
            operatorOption: currentOperators[operatorPopup.indexOfSelectedItem],
            value: valueField.stringValue
        )
    }

    private var currentOperators: [SearchOperatorOption] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true
        addButton.target = self
        addButton.action = #selector(addClicked)
        removeButton.target = self
        removeButton.action = #selector(removeClicked)
        addButton.bezelStyle = .texturedRounded
        removeButton.bezelStyle = .texturedRounded

        fieldPopup.addItems(withTitles: SearchFieldOption.allCases.map(\.displayName))
        fieldPopup.target = self
        fieldPopup.action = #selector(fieldChanged)

        operatorPopup.target = self
        operatorPopup.action = #selector(operatorChanged)

        valueField.target = self
        valueField.action = #selector(valueChanged)
        valueField.stringValue = ".lookin"

        addSubview(addButton)
        addSubview(removeButton)
        addSubview(fieldPopup)
        addSubview(operatorPopup)
        addSubview(valueField)

        addButton.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(30)
        }
        removeButton.snp.makeConstraints { make in
            make.leading.equalTo(addButton.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(30)
        }
        fieldPopup.snp.makeConstraints { make in
            make.leading.equalTo(removeButton.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(150)
        }
        operatorPopup.snp.makeConstraints { make in
            make.leading.equalTo(fieldPopup.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.width.equalTo(180)
        }
        valueField.snp.makeConstraints { make in
            make.leading.equalTo(operatorPopup.snp.trailing).offset(12)
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.height.equalTo(32)
        }

        fieldPopup.selectItem(withTitle: SearchFieldOption.name.displayName)
        reloadOperators()
    }

    private func reloadOperators() {
        let selectedField = SearchFieldOption.allCases[fieldPopup.indexOfSelectedItem]
        currentOperators = selectedField.supportedOperators
        operatorPopup.removeAllItems()
        operatorPopup.addItems(withTitles: currentOperators.map(\.displayName))
        operatorPopup.selectItem(at: 0)
        onChange?()
    }

    @objc
    private func addClicked() { onAdd?() }

    @objc
    private func removeClicked() { onRemove?() }

    @objc
    private func fieldChanged() { reloadOperators() }

    @objc
    private func operatorChanged() { onChange?() }

    @objc
    private func valueChanged() { onChange?() }
}

private enum SearchScopeOption {
    case startupVolume
    case homeFolder
}

private enum SearchFieldOption: CaseIterable {
    case comments
    case createdDate
    case `extension`
    case fileSize
    case folderNames
    case invisibleItems
    case kind
    case lastModifiedDate
    case name
    case nameWithoutExtension
    case packageContents
    case path
    case script
    case tag
    case textContent
    case trashedContents

    var displayName: String {
        switch self {
        case .comments: return "Comments"
        case .createdDate: return "Created date"
        case .extension: return "Extension"
        case .fileSize: return "File size"
        case .folderNames: return "Folder names"
        case .invisibleItems: return "Invisible items"
        case .kind: return "Kind"
        case .lastModifiedDate: return "Last modified date"
        case .name: return "Name"
        case .nameWithoutExtension: return "Name without Extension"
        case .packageContents: return "Package contents"
        case .path: return "Path"
        case .script: return "Script"
        case .tag: return "Tag"
        case .textContent: return "Text content"
        case .trashedContents: return "Trashed contents"
        }
    }

    var supportedOperators: [SearchOperatorOption] {
        switch self {
        case .createdDate, .lastModifiedDate, .fileSize, .invisibleItems, .packageContents, .trashedContents:
            return [.is, .doesNotContain]
        default:
            return SearchOperatorOption.allCases
        }
    }
}

private enum SearchOperatorOption: CaseIterable {
    case contains
    case containsPhrase
    case beginsWith
    case endsWith
    case `is`
    case doesNotContain
    case containsWords
    case matchesPattern
    case containsAnyOf
    case beginsWithAnyOf
    case endsWithAnyOf
    case isAnyOf
    case matchesRegex
    case doesNotMatchRegex

    var displayName: String {
        switch self {
        case .contains: return "contains"
        case .containsPhrase: return "contains phrase"
        case .beginsWith: return "begins with"
        case .endsWith: return "ends with"
        case .is: return "is"
        case .doesNotContain: return "doesn't contain"
        case .containsWords: return "contains words"
        case .matchesPattern: return "matches pattern"
        case .containsAnyOf: return "contains any of"
        case .beginsWithAnyOf: return "begins with any of"
        case .endsWithAnyOf: return "ends with any of"
        case .isAnyOf: return "is any of"
        case .matchesRegex: return "matches RegEx"
        case .doesNotMatchRegex: return "doesn't match RegEx"
        }
    }

    var isRegex: Bool {
        self == .matchesRegex || self == .doesNotMatchRegex
    }
}
