import AppKit
import Combine
import SnapKit

final class SpecialFoldersWindowController: NSWindowController {
    private let themeController: ThemeController
    private var cancellables = Set<AnyCancellable>()

    convenience init(store: SpecialFoldersStore) {
        self.init(store: store, themeController: .shared)
    }

    init(
        store: SpecialFoldersStore = .shared,
        themeController: ThemeController = .shared
    ) {
        self.themeController = themeController
        let rootViewController = SpecialFoldersEditorViewController(store: store)
        _ = rootViewController.view
        rootViewController.view.frame = NSRect(
            x: 0,
            y: 0,
            width: SpecialFoldersEditorViewController.defaultWindowWidth,
            height: 1
        )
        rootViewController.view.layoutSubtreeIfNeeded()
        let window = NSWindow(contentViewController: rootViewController)
        window.setContentSize(
            NSSize(
                width: SpecialFoldersEditorViewController.defaultWindowWidth,
                height: rootViewController.view.fittingSize.height
            )
        )
        window.title = L10n.string("preferences.search.special_folders.window_title")
        window.center()
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        super.init(window: window)
        bindTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func bindTheme() {
        applyCurrentTheme()
        themeController.publisher
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyCurrentTheme()
            }
            .store(in: &cancellables)
    }

    private func applyCurrentTheme() {
        themeController.apply(theme: themeController.currentTheme, to: window)
    }
}

final class SpecialFoldersEditorViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    static let defaultWindowWidth: CGFloat = 720

    private enum Column {
        static let path = NSUserInterfaceItemIdentifier("path")
        static let disposition = NSUserInterfaceItemIdentifier("disposition")
    }

    private static let dragType = NSPasteboard.PasteboardType("cn.vanjay.FileHound.special-folder-row")
    private static let outerInset: CGFloat = 20
    private static let defaultVisibleRowCount: CGFloat = 3.5
    private static let listControlButtonSize = NSSize(width: 24, height: 24)

    private let store: SpecialFoldersStore
    private var configuration: SpecialFoldersConfiguration
    private let scrollView = NSScrollView()
    private let tableContainerView = NSView()
    private let tableView = SpecialFoldersTableView()
    private let addButton = SpecialFoldersControlButton(symbolName: "plus")
    private let removeButton = SpecialFoldersControlButton(symbolName: "minus")
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
        let containerView = AppearanceAwareView()
        containerView.backgroundColorProvider = { appearance in
            .fhWindowSurface(for: appearance)
        }
        containerView.onAppearanceChange = { [weak self] in
            self?.applyAppearance()
            self?.tableView.reloadData()
        }
        let sectionView = PreferencesSectionView(
            title: L10n.string("preferences.search.special_folders.title"),
            subtitle: L10n.string("preferences.search.special_folders.subtitle")
        )

        configureTable()
        configureControls()

        containerView.addSubview(sectionView)
        sectionView.addSubview(tableContainerView)
        sectionView.addSubview(addButton)
        sectionView.addSubview(removeButton)
        tableContainerView.addSubview(scrollView)
        tableContainerView.addSubview(emptyStateLabel)

        sectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Self.outerInset)
        }
        tableContainerView.snp.makeConstraints { make in
            make.top.equalTo(sectionView.contentGuide)
            make.leading.trailing.equalTo(sectionView.contentGuide).inset(6)
            make.bottom.equalTo(addButton.snp.top).offset(-12)
            make.height.equalTo(defaultListHeight)
        }
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        emptyStateLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().inset(20)
            make.trailing.lessThanOrEqualToSuperview().inset(20)
        }
        addButton.snp.makeConstraints { make in
            make.leading.equalTo(sectionView.contentGuide).inset(6)
            make.bottom.equalTo(sectionView.contentGuide)
            make.size.equalTo(Self.listControlButtonSize)
        }
        removeButton.snp.makeConstraints { make in
            make.leading.equalTo(addButton.snp.trailing).offset(6)
            make.centerY.equalTo(addButton)
            make.size.equalTo(Self.listControlButtonSize)
        }

        view = containerView
        applyAppearance()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadTable()
    }

    private func configureTable() {
        let pathColumn = NSTableColumn(identifier: Column.path)
        pathColumn.title = ""
        pathColumn.resizingMask = .autoresizingMask
        pathColumn.width = 440

        let dispositionColumn = NSTableColumn(identifier: Column.disposition)
        dispositionColumn.title = ""
        dispositionColumn.resizingMask = .autoresizingMask
        dispositionColumn.width = 170

        tableView.addTableColumn(pathColumn)
        tableView.addTableColumn(dispositionColumn)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92)
        tableView.rowHeight = 34
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.focusRingType = .none
        tableView.setAccessibilityElement(true)
        tableView.setAccessibilityIdentifier("SpecialFoldersTable")
        tableView.menuProvider = { [weak self] event in
            self?.contextMenu(for: event)
        }
        tableView.registerForDraggedTypes([Self.dragType])

        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = tableView

        emptyStateLabel.stringValue = L10n.string("preferences.search.special_folders.empty")
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.alignment = .center
    }

    private func configureControls() {
        addButton.target = self
        addButton.action = #selector(addFolder)
        addButton.setAccessibilityIdentifier("SpecialFoldersAddButton")
        addButton.toolTip = L10n.string("preferences.search.special_folders.add")

        removeButton.target = self
        removeButton.action = #selector(removeSelectedRules)
        removeButton.setAccessibilityIdentifier("SpecialFoldersRemoveButton")
        removeButton.toolTip = L10n.string("preferences.search.special_folders.remove")
        removeButton.isEnabled = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        configuration.rules.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard configuration.rules.indices.contains(row), let tableColumn else {
            return nil
        }

        let rule = configuration.rules[row]
        switch tableColumn.identifier {
        case Column.path:
            let cell = tableView.makeView(
                withIdentifier: SpecialFolderPathCellView.identifier,
                owner: self
            ) as? SpecialFolderPathCellView ?? SpecialFolderPathCellView()
            cell.render(path: rule.path)
            return cell
        case Column.disposition:
            let cell = tableView.makeView(
                withIdentifier: SpecialFolderDispositionCellView.identifier,
                owner: self
            ) as? SpecialFolderDispositionCellView ?? SpecialFolderDispositionCellView()
            cell.render(disposition: rule.disposition)
            cell.onDispositionChange = { [weak self] disposition in
                self?.updateRule(id: rule.id, disposition: disposition)
            }
            return cell
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SpecialFoldersTableRowView(row: row)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        syncControls()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard configuration.rules.indices.contains(row) else {
            return nil
        }

        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.dragType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard
            let sourceString = info.draggingPasteboard.string(forType: Self.dragType),
            let sourceIndex = Int(sourceString)
        else {
            return false
        }

        moveRuleForDrop(from: sourceIndex, toProposedRow: row)
        return true
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

    @objc
    private func removeSelectedRules() {
        removeRules(at: tableView.selectedRowIndexes)
    }

    @objc
    private func deleteSelectedRulesFromContextMenu() {
        removeSelectedRules()
    }

    private func contextMenu(for event: NSEvent) -> NSMenu? {
        let point = tableView.convert(event.locationInWindow, from: nil)
        let row = tableView.row(at: point)
        if row >= 0, tableView.selectedRowIndexes.contains(row) == false {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        guard tableView.selectedRowIndexes.isEmpty == false else {
            return nil
        }

        let menu = NSMenu()
        let item = NSMenuItem(
            title: L10n.string("preferences.search.special_folders.remove"),
            action: #selector(deleteSelectedRulesFromContextMenu),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    private func addRule(path: String, disposition: SpecialFolderDisposition) {
        let normalizedPath = normalize(path: path)
        if let existingIndex = configuration.rules.firstIndex(where: { normalize(path: $0.path) == normalizedPath }) {
            reloadTable(selecting: IndexSet(integer: existingIndex))
            tableView.scrollRowToVisible(existingIndex)
            return
        }

        configuration.rules.append(SpecialFolderRule(path: normalizedPath, disposition: disposition))
        persistAndReload(selecting: IndexSet(integer: configuration.rules.count - 1))
    }

    private func updateRule(id: UUID, disposition: SpecialFolderDisposition) {
        guard let index = configuration.rules.firstIndex(where: { $0.id == id }) else {
            return
        }

        configuration.rules[index].disposition = disposition
        persistAndReload(selecting: tableView.selectedRowIndexes)
    }

    private func removeRules(at indexes: IndexSet) {
        guard indexes.isEmpty == false else {
            return
        }

        configuration.rules = configuration.rules.enumerated().compactMap { index, rule in
            indexes.contains(index) ? nil : rule
        }
        persistAndReload()
    }

    private func moveRuleForDrop(from sourceIndex: Int, toProposedRow proposedDestinationIndex: Int) {
        guard configuration.rules.indices.contains(sourceIndex) else {
            return
        }

        var destinationIndex = min(max(proposedDestinationIndex, 0), configuration.rules.count)
        if destinationIndex == sourceIndex || destinationIndex == sourceIndex + 1 {
            return
        }

        let rule = configuration.rules.remove(at: sourceIndex)
        if destinationIndex > sourceIndex {
            destinationIndex -= 1
        }
        configuration.rules.insert(rule, at: destinationIndex)
        persistAndReload(selecting: IndexSet(integer: destinationIndex))
    }

    private func moveRuleToFinalIndex(from sourceIndex: Int, to destinationIndex: Int) {
        guard configuration.rules.indices.contains(sourceIndex) else {
            return
        }

        let clampedDestination = min(max(destinationIndex, 0), configuration.rules.count - 1)
        if sourceIndex == clampedDestination {
            return
        }

        let rule = configuration.rules.remove(at: sourceIndex)
        configuration.rules.insert(rule, at: clampedDestination)
        persistAndReload(selecting: IndexSet(integer: clampedDestination))
    }

    private func persistAndReload(selecting selection: IndexSet = []) {
        try? store.save(configuration)
        reloadTable(selecting: selection)
    }

    private func reloadTable(selecting selection: IndexSet = []) {
        tableView.reloadData()
        let validSelection = selection.reduce(into: IndexSet()) { result, index in
            if configuration.rules.indices.contains(index) {
                result.insert(index)
            }
        }
        if validSelection.isEmpty == false {
            tableView.selectRowIndexes(validSelection, byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        emptyStateLabel.isHidden = configuration.rules.isEmpty == false
        syncControls()
    }

    private func syncControls() {
        removeButton.isEnabled = tableView.selectedRowIndexes.isEmpty == false
    }

    private var defaultListHeight: CGFloat {
        tableView.rowHeight * Self.defaultVisibleRowCount
    }

    private func normalize(path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardized.isEmpty {
            return path
        }
        return standardized
    }

    private func applyAppearance() {
        (view as? AppearanceAwareView)?.applyBackgroundAppearance()
        tableView.backgroundColor = Self.listBackgroundColor(for: view.effectiveAppearance)
    }

    private static func listBackgroundColor(for appearance: NSAppearance) -> NSColor {
        NSColor.fhPanelSurface(for: appearance, alpha: 0.95)
    }

    fileprivate static func rowBackgroundColor(for row: Int, appearance: NSAppearance) -> NSColor {
        if appearance.fhIsDarkMode {
            let white: CGFloat = row.isMultiple(of: 2) ? 0.20 : 0.25
            return NSColor(calibratedWhite: white, alpha: 0.98)
        }

        let white: CGFloat = row.isMultiple(of: 2) ? 0.975 : 0.925
        return NSColor(calibratedWhite: white, alpha: 0.98)
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
        removeRules(at: IndexSet(integer: index))
    }

    @objc(debugDeleteSelectedRulesFromContextMenu)
    func debugDeleteSelectedRulesFromContextMenu() {
        deleteSelectedRulesFromContextMenu()
    }

    @objc(debugMoveRuleFromIndex:toIndex:)
    func debugMoveRule(fromIndex: NSNumber, toIndex: NSNumber) {
        moveRuleToFinalIndex(from: fromIndex.intValue, to: toIndex.intValue)
    }

    var debugRules: [SpecialFolderRule] {
        configuration.rules
    }

    var debugListBorderType: NSBorderType {
        scrollView.borderType
    }

    var debugAddButtonImageAlignmentOffset: CGFloat {
        addButton.debugImageAlignmentOffset
    }

    var debugRemoveButtonImageAlignmentOffset: CGFloat {
        removeButton.debugImageAlignmentOffset
    }

    var debugAddButtonSize: NSSize {
        addButton.bounds.size
    }

    var debugRemoveButtonSize: NSSize {
        removeButton.bounds.size
    }

    func debugRootBackgroundHex(for appearanceName: NSAppearance.Name) -> String {
        let appearance = NSAppearance(named: appearanceName)
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)!
        return NSColor.fhWindowSurface(for: appearance).fhResolvedHex(for: appearanceName)
    }

    func debugListBackgroundHex(for appearanceName: NSAppearance.Name) -> String {
        let appearance = NSAppearance(named: appearanceName)
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)!
        return Self.listBackgroundColor(for: appearance).fhResolvedHex(for: appearanceName)
    }

    func debugRowBackgroundHex(for row: Int, appearanceName: NSAppearance.Name) -> String {
        let appearance = NSAppearance(named: appearanceName)
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)!
        return Self.rowBackgroundColor(for: row, appearance: appearance).fhResolvedHex(for: appearanceName)
    }
}
#endif

private final class SpecialFoldersTableView: NSTableView {
    var menuProvider: ((NSEvent) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(event)
    }
}

private final class SpecialFoldersTableRowView: NSTableRowView {
    private let rowIndex: Int

    init(row: Int) {
        self.rowIndex = row
        super.init(frame: .zero)
        selectionHighlightStyle = .regular
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawBackground(in dirtyRect: NSRect) {
        SpecialFoldersEditorViewController.rowBackgroundColor(for: rowIndex, appearance: effectiveAppearance)
            .fhResolvedColor(for: effectiveAppearance)
            .setFill()
        dirtyRect.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor
            .withAlphaComponent(effectiveAppearance.fhIsDarkMode ? 0.60 : 0.85)
            .fhResolvedColor(for: effectiveAppearance)
            .setFill()
        dirtyRect.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private final class SpecialFolderPathCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SpecialFolderPathCellView")

    private let pathLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        identifier = Self.identifier
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(pathLabel)
        pathLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(path: String) {
        pathLabel.stringValue = path
    }
}

private final class SpecialFolderDispositionCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SpecialFolderDispositionCellView")

    private let popup = NSPopUpButton()
    var onDispositionChange: ((SpecialFolderDisposition) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        identifier = Self.identifier
        popup.addItems(withTitles: SpecialFolderDisposition.menuTitles)
        popup.target = self
        popup.action = #selector(dispositionChanged)
        addSubview(popup)
        popup.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
            make.width.equalTo(150)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(disposition: SpecialFolderDisposition) {
        popup.selectItem(at: SpecialFolderDisposition.menuOrder.firstIndex(of: disposition) ?? 1)
    }

    @objc
    private func dispositionChanged() {
        let index = max(popup.indexOfSelectedItem, 0)
        onDispositionChange?(SpecialFolderDisposition.menuOrder[index])
    }
}

private final class SpecialFoldersControlButton: NSButton {
    init(symbolName: String) {
        super.init(frame: .zero)

        cell = CenteredImageButtonCell()
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular, scale: .small)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        image?.size = NSSize(width: 10, height: 10)
        imageScaling = .scaleProportionallyDown
        imagePosition = .imageOnly
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isEnabled: Bool {
        didSet {
            updateAppearance()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            updateAppearance()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.borderColor = NSColor.separatorColor.fhResolvedCGColor(for: effectiveAppearance)
        layer?.backgroundColor = (isHighlighted ? NSColor.controlAccentColor.withAlphaComponent(0.1) : NSColor.controlBackgroundColor)
            .fhResolvedCGColor(for: effectiveAppearance)
        contentTintColor = isEnabled ? .labelColor : .disabledControlTextColor
    }

    #if DEBUG
    var debugImageAlignmentOffset: CGFloat {
        guard let cell = cell as? CenteredImageButtonCell else {
            return .greatestFiniteMagnitude
        }

        let imageRect = cell.imageRect(forBounds: bounds)
        return max(abs(imageRect.midX - bounds.midX), abs(imageRect.midY - bounds.midY))
    }
    #endif
}

private final class CenteredImageButtonCell: NSButtonCell {
    override func imageRect(forBounds rect: NSRect) -> NSRect {
        let imageSize = image?.size ?? NSSize(width: 10, height: 10)
        return NSRect(
            x: round((rect.width - imageSize.width) / 2),
            y: round((rect.height - imageSize.height) / 2),
            width: imageSize.width,
            height: imageSize.height
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        .zero
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
