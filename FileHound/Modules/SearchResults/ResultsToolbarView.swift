import AppKit
import SnapKit

final class ResultsToolbarView: NSView {
    static let supportedSortFields: [SearchResultsViewModel.SortField] = [
        .name,
        .dateModified,
        .dateCreated,
        .lastOpened,
        .dateAdded,
        .kind,
        .size,
        .tags,
        .enclosingFolder,
        .path
    ]

    let gridButton = ResultsToolbarButton(symbolName: "square.grid.2x2", accessibilityID: "ResultsModeGridButton")
    let tableButton = ResultsToolbarButton(symbolName: "list.bullet.rectangle", accessibilityID: "ResultsModeTableButton")
    let treeButton = ResultsToolbarButton(symbolName: "list.bullet.indent", accessibilityID: "ResultsModeTreeButton")
    let invisiblesButton = ResultsToolbarToggleButton(symbolName: "eye.slash", accessibilityID: "ResultsShowInvisiblesButton")
    let packageButton = ResultsToolbarToggleButton(symbolName: "shippingbox", accessibilityID: "ResultsShowPackagesButton")
    let trashedButton = ResultsToolbarToggleButton(symbolName: "trash", accessibilityID: "ResultsShowTrashedButton")
    let filterField = NSSearchField()
    let previewSlider = NSSlider(value: 72, minValue: 32, maxValue: 128, target: nil, action: nil)
    let sortByPopup = NSPopUpButton()
    /// 导出当前视图中的结果（CSV / 纯文本）
    let exportButton = NSButton()
    private let topBar = NSStackView()
    private let secondaryBar = NSView()
    private let previewLabel = NSTextField(labelWithString: L10n.string("results.toolbar.preview_size"))
    private let sortLabel = NSTextField(labelWithString: L10n.string("results.toolbar.sort_by"))
    /// 分组标题（显示 / 包括 / 过滤），切换语言时需要刷新
    private let modeGroupLabel = NSTextField(labelWithString: "")
    private let optionsGroupLabel = NSTextField(labelWithString: "")
    private let filterGroupLabel = NSTextField(labelWithString: "")
    private var secondaryBarHeightConstraint: Constraint?
    private var secondaryBarTopConstraint: Constraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        filterField.setAccessibilityIdentifier("ResultsFilterField")
        previewSlider.controlSize = .small
        previewSlider.isContinuous = true
        previewSlider.setAccessibilityIdentifier("ResultsPreviewSlider")
        sortByPopup.setAccessibilityIdentifier("ResultsSortByPopup")
        sortByPopup.addItems(withTitles: Self.supportedSortFields.map(Self.title(for:)))
        sortByPopup.selectItem(at: 0)
        exportButton.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        exportButton.imagePosition = .imageOnly
        exportButton.bezelStyle = .texturedRounded
        exportButton.controlSize = .small
        exportButton.setButtonType(.momentaryPushIn)
        exportButton.setAccessibilityIdentifier("ResultsExportButton")
        [previewLabel, sortLabel].forEach {
            $0.font = .systemFont(ofSize: 11, weight: .medium)
            $0.textColor = .secondaryLabelColor
        }

        let modeGroup = makeGroupedStack(titleLabel: modeGroupLabel, views: [gridButton, tableButton, treeButton])
        let optionsGroup = makeGroupedStack(titleLabel: optionsGroupLabel, views: [invisiblesButton, packageButton, trashedButton])
        let filterGroup = makeGroupedStack(titleLabel: filterGroupLabel, views: [filterField])

        topBar.orientation = .horizontal
        topBar.alignment = .top
        topBar.spacing = 18
        topBar.addArrangedSubview(modeGroup)
        topBar.addArrangedSubview(optionsGroup)
        topBar.addArrangedSubview(NSView())
        topBar.addArrangedSubview(filterGroup)

        wantsLayer = true

        addSubview(topBar)
        addSubview(secondaryBar)
        secondaryBar.addSubview(previewLabel)
        secondaryBar.addSubview(previewSlider)
        secondaryBar.addSubview(exportButton)
        secondaryBar.addSubview(sortLabel)
        secondaryBar.addSubview(sortByPopup)

        topBar.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview().inset(10)
        }
        secondaryBar.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(10)
            secondaryBarTopConstraint = make.top.equalTo(topBar.snp.bottom).offset(8).constraint
            secondaryBarHeightConstraint = make.height.equalTo(22).constraint
        }
        previewLabel.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
        }
        previewSlider.snp.makeConstraints { make in
            make.leading.equalTo(previewLabel.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.width.equalTo(150)
        }
        exportButton.snp.makeConstraints { make in
            make.trailing.equalTo(sortLabel.snp.leading).offset(-16)
            make.centerY.equalToSuperview()
        }
        sortLabel.snp.makeConstraints { make in
            make.trailing.equalTo(sortByPopup.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }
        sortByPopup.snp.makeConstraints { make in
            make.trailing.centerY.equalToSuperview()
            make.width.equalTo(170)
        }

        filterField.snp.makeConstraints { make in
            make.width.equalTo(260)
        }

        reloadLocalizedStrings()
        apply(mode: .grid)
        applyBackgroundAppearance()
    }

    /// 刷新全部文案：应用内切换语言时调用。无障碍标签使用本地化文案，accessibilityIdentifier 保留给 UI 测试
    func reloadLocalizedStrings() {
        filterField.placeholderString = L10n.string("results.toolbar.filter")
        previewLabel.stringValue = L10n.string("results.toolbar.preview_size")
        sortLabel.stringValue = L10n.string("results.toolbar.sort_by")
        modeGroupLabel.stringValue = L10n.string("results.toolbar.view")
        optionsGroupLabel.stringValue = L10n.string("results.toolbar.show")
        filterGroupLabel.stringValue = L10n.string("results.toolbar.filter")

        let buttonTitles: [(NSButton, String)] = [
            (gridButton, L10n.string("results.toolbar.grid")),
            (tableButton, L10n.string("results.mode.list")),
            (treeButton, L10n.string("results.mode.tree")),
            (invisiblesButton, L10n.string("results.toolbar.show_invisibles")),
            (packageButton, L10n.string("results.toolbar.show_package_contents")),
            (trashedButton, L10n.string("results.toolbar.show_trashed")),
            (exportButton, L10n.string("results.export.menu_title"))
        ]
        for (button, title) in buttonTitles {
            button.toolTip = title
            button.setAccessibilityLabel(title)
        }

        // 重建排序菜单标题，保持当前选中项
        let selectedIndex = sortByPopup.indexOfSelectedItem
        sortByPopup.removeAllItems()
        sortByPopup.addItems(withTitles: Self.supportedSortFields.map(Self.title(for:)))
        sortByPopup.selectItem(at: max(selectedIndex, 0))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackgroundAppearance()
    }

    func apply(mode: SearchResultsViewModel.Mode) {
        gridButton.state = mode == .grid ? .on : .off
        tableButton.state = mode == .table ? .on : .off
        treeButton.state = mode == .tree ? .on : .off

        secondaryBar.isHidden = false
        previewSlider.isHidden = mode != .grid
        previewLabel.isHidden = mode != .grid
        sortByPopup.isHidden = false
        sortLabel.isHidden = false
        secondaryBarHeightConstraint?.update(offset: 22)
        secondaryBarTopConstraint?.update(offset: 8)
    }

    func selectSortField(_ field: SearchResultsViewModel.SortField) {
        if let index = Self.supportedSortFields.firstIndex(of: field) {
            sortByPopup.selectItem(at: index)
        }
    }

    var selectedSortField: SearchResultsViewModel.SortField {
        Self.supportedSortFields[safe: sortByPopup.indexOfSelectedItem] ?? .name
    }

    private func makeGroupedStack(titleLabel: NSTextField?, views: [NSView]) -> NSView {
        let container = NSView()
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        container.addSubview(stack)

        if let label = titleLabel {
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            container.addSubview(label)
            label.snp.makeConstraints { make in
                make.leading.top.equalToSuperview()
            }
            stack.snp.makeConstraints { make in
                make.leading.equalToSuperview()
                make.top.equalTo(label.snp.bottom).offset(4)
                make.trailing.bottom.equalToSuperview()
            }
            return container
        }

        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        return container
    }

    private static func title(for field: SearchResultsViewModel.SortField) -> String {
        switch field {
        case .name:
            return L10n.string("results.column.name")
        case .dateModified:
            return L10n.string("results.column.modified")
        case .dateCreated:
            return L10n.string("results.column.created")
        case .lastOpened:
            return L10n.string("results.column.last_opened")
        case .dateAdded:
            return L10n.string("results.column.added")
        case .kind:
            return L10n.string("results.column.kind")
        case .size:
            return L10n.string("results.column.size")
        case .tags:
            return L10n.string("results.column.tags")
        case .enclosingFolder:
            return L10n.string("results.column.enclosing_folder")
        case .path:
            return L10n.string("results.column.path")
        }
    }

    private func applyBackgroundAppearance(resolvedAgainst appearance: NSAppearance? = nil) {
        let resolvedAppearance = appearance ?? effectiveAppearance
        layer?.backgroundColor = NSColor.fhPanelSurface(for: resolvedAppearance, alpha: 0.94).fhResolvedCGColor(for: resolvedAppearance)
    }
}

#if DEBUG
extension ResultsToolbarView {
    var debugPreviewLabelText: String {
        previewLabel.stringValue
    }

    var debugLayerBackgroundColor: CGColor? {
        layer?.backgroundColor
    }

    func debugBackgroundHex(for appearanceName: NSAppearance.Name) -> String {
        let appearance = NSAppearance(named: appearanceName)
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)!
        return NSColor.fhPanelSurface(for: appearance, alpha: 0.94).fhResolvedHex(for: appearanceName)
    }
}
#endif

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

final class ResultsToolbarButton: NSButton {
    init(symbolName: String, accessibilityID: String) {
        super.init(frame: .zero)
        // 无障碍标签由 ResultsToolbarView.reloadLocalizedStrings 设置为本地化文案，这里只设置 UI 测试使用的 identifier
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        bezelStyle = .texturedRounded
        imagePosition = .imageOnly
        setButtonType(.toggle)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityIdentifier(accessibilityID)
        updateAppearance()
    }

    override var state: NSControl.StateValue {
        didSet {
            updateAppearance()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        contentTintColor = state == .on ? .controlAccentColor : .secondaryLabelColor
    }
}

final class ResultsToolbarToggleButton: NSButton {
    init(symbolName: String, accessibilityID: String) {
        super.init(frame: .zero)
        // 无障碍标签由 ResultsToolbarView.reloadLocalizedStrings 设置为本地化文案，这里只设置 UI 测试使用的 identifier
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        bezelStyle = .texturedRounded
        imagePosition = .imageOnly
        setButtonType(.toggle)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityIdentifier(accessibilityID)
        updateAppearance()
    }

    override var state: NSControl.StateValue {
        didSet {
            updateAppearance()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        contentTintColor = state == .on ? .controlAccentColor : .secondaryLabelColor
    }
}
