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
    private let topBar = NSStackView()
    private let secondaryBar = NSView()
    private let previewLabel = NSTextField(labelWithString: "Preview Size:")
    private let sortLabel = NSTextField(labelWithString: "Sort By")
    private var secondaryBarHeightConstraint: Constraint?
    private var secondaryBarTopConstraint: Constraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        filterField.setAccessibilityIdentifier("ResultsFilterField")
        filterField.placeholderString = "Filter"
        gridButton.toolTip = "Grid View"
        tableButton.toolTip = "List View"
        treeButton.toolTip = "Tree View"
        invisiblesButton.toolTip = "Show Invisible Items"
        packageButton.toolTip = "Show Package Contents"
        trashedButton.toolTip = "Show Trashed Items"
        previewSlider.controlSize = .small
        previewSlider.isContinuous = true
        previewSlider.setAccessibilityIdentifier("ResultsPreviewSlider")
        sortByPopup.setAccessibilityIdentifier("ResultsSortByPopup")
        sortByPopup.addItems(withTitles: Self.supportedSortFields.map(Self.title(for:)))
        sortByPopup.selectItem(at: 0)
        [previewLabel, sortLabel].forEach {
            $0.font = .systemFont(ofSize: 11, weight: .medium)
            $0.textColor = .secondaryLabelColor
        }

        let modeGroup = makeGroupedStack(title: "View", views: [gridButton, tableButton, treeButton])
        let optionsGroup = makeGroupedStack(title: "Show", views: [invisiblesButton, packageButton, trashedButton])
        let filterGroup = makeGroupedStack(title: "Filter", views: [filterField])

        topBar.orientation = .horizontal
        topBar.alignment = .top
        topBar.spacing = 18
        topBar.addArrangedSubview(modeGroup)
        topBar.addArrangedSubview(optionsGroup)
        topBar.addArrangedSubview(NSView())
        topBar.addArrangedSubview(filterGroup)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor

        addSubview(topBar)
        addSubview(secondaryBar)
        secondaryBar.addSubview(previewLabel)
        secondaryBar.addSubview(previewSlider)
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

        apply(mode: .grid)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    private func makeGroupedStack(title: String?, views: [NSView]) -> NSView {
        let container = NSView()
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        container.addSubview(stack)

        if let title {
            let label = NSTextField(labelWithString: title)
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
            return "Name"
        case .dateModified:
            return "Date Modified"
        case .dateCreated:
            return "Date Created"
        case .lastOpened:
            return "Last Opened"
        case .dateAdded:
            return "Date Added"
        case .kind:
            return "Kind"
        case .size:
            return "Size"
        case .tags:
            return "Tags"
        case .enclosingFolder:
            return "Enclosing Folder"
        case .path:
            return "Path"
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

final class ResultsToolbarButton: NSButton {
    init(symbolName: String, accessibilityID: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityID)
        bezelStyle = .texturedRounded
        imagePosition = .imageOnly
        setButtonType(.toggle)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityIdentifier(accessibilityID)
        setAccessibilityLabel(accessibilityID)
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
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityID)
        bezelStyle = .texturedRounded
        imagePosition = .imageOnly
        setButtonType(.toggle)
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityIdentifier(accessibilityID)
        setAccessibilityLabel(accessibilityID)
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
