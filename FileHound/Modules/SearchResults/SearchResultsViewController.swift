import AppKit
import CoreServices
import QuickLookUI
import SnapKit

final class SearchResultsViewController: NSViewController, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let viewModel: SearchResultsViewModel
    private let expandsFoldersWhenShowingResults: Bool
    private let gridController = ResultsCollectionViewController()
    private let tableController = ResultsTableViewController()
    private let treeController = ResultsOutlineViewController()
    private let toolbarView = ResultsToolbarView()
    private let containerView = NSView()
    private let statusBarView = ResultsStatusBarView()
    private let emptyStateLabel = NSTextField(labelWithString: L10n.string("results.empty"))
    private lazy var actionController = ResultActionController(confirmationPresenter: { [weak self] request in
        self?.confirm(request: request) ?? false
    })
    private var menuHandlers: [MenuActionHandler] = []
    private var quickLookURLs: [URL] = []

    init(
        viewModel: SearchResultsViewModel,
        expandsFoldersWhenShowingResults: Bool = false
    ) {
        self.viewModel = viewModel
        self.expandsFoldersWhenShowingResults = expandsFoldersWhenShowingResults
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView()
        rootView.setAccessibilityIdentifier("SearchResultsRootView")
        rootView.setAccessibilityElement(true)

        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1).cgColor

        addChild(gridController)
        addChild(tableController)
        addChild(treeController)
        containerView.addSubview(gridController.view)
        containerView.addSubview(tableController.view)
        containerView.addSubview(treeController.view)
        containerView.addSubview(emptyStateLabel)

        emptyStateLabel.alignment = .center
        emptyStateLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.isHidden = true

        toolbarView.gridButton.target = self
        toolbarView.gridButton.action = #selector(showGridMode)
        toolbarView.tableButton.target = self
        toolbarView.tableButton.action = #selector(showTableMode)
        toolbarView.treeButton.target = self
        toolbarView.treeButton.action = #selector(showTreeMode)
        toolbarView.filterField.target = self
        toolbarView.filterField.action = #selector(filterChanged)
        toolbarView.previewSlider.target = self
        toolbarView.previewSlider.action = #selector(previewSizeChanged)
        toolbarView.sortByPopup.target = self
        toolbarView.sortByPopup.action = #selector(sortByChanged)
        toolbarView.invisiblesButton.target = self
        toolbarView.invisiblesButton.action = #selector(toggleInvisibles)
        toolbarView.packageButton.target = self
        toolbarView.packageButton.action = #selector(togglePackages)
        toolbarView.trashedButton.target = self
        toolbarView.trashedButton.action = #selector(toggleTrashed)

        rootView.addSubview(toolbarView)
        rootView.addSubview(containerView)
        rootView.addSubview(statusBarView)

        toolbarView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
        }
        containerView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.top.equalTo(toolbarView.snp.bottom)
            make.bottom.equalTo(statusBarView.snp.top)
        }
        statusBarView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(28)
        }
        gridController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        tableController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        treeController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        emptyStateLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        treeController.expandsFoldersOnReload = expandsFoldersWhenShowingResults

        gridController.onSelectionChange = { [weak self] item in
            self?.viewModel.selectedItem = item
        }
        tableController.onSelectionChange = { [weak self] item in
            self?.viewModel.selectedItem = item
        }
        treeController.onSelectionChange = { [weak self] item in
            self?.viewModel.selectedItem = item
        }
        gridController.onSelectionSetChange = { [weak self] items in
            self?.updateSelection(items)
        }
        tableController.onSelectionSetChange = { [weak self] items in
            self?.updateSelection(items)
        }
        treeController.onSelectionSetChange = { [weak self] items in
            self?.updateSelection(items)
        }
        gridController.contextMenuProvider = { [weak self] items in
            self?.makeContextMenu(for: items)
        }
        tableController.contextMenuProvider = { [weak self] items in
            self?.makeContextMenu(for: items)
        }
        treeController.contextMenuProvider = { [weak self] items in
            self?.makeContextMenu(for: items)
        }
        gridController.onOpenItems = { [weak self] items in
            self?.open(items: items, applicationURL: nil)
        }
        tableController.onOpenItems = { [weak self] items in
            self?.open(items: items, applicationURL: nil)
        }
        treeController.onOpenItems = { [weak self] items in
            self?.open(items: items, applicationURL: nil)
        }
        gridController.onQuickLookRequest = { [weak self] items in
            self?.showQuickLook(items: items)
        }
        tableController.onSortChange = { [weak self] field, order in
            self?.applySort(field: field, order: order)
        }
        tableController.onQuickLookRequest = { [weak self] items in
            self?.showQuickLook(items: items)
        }
        treeController.onSortChange = { [weak self] field, order in
            self?.applySort(field: field, order: order)
        }
        treeController.onQuickLookRequest = { [weak self] items in
            self?.showQuickLook(items: items)
        }

        viewModel.onModeChange = { [weak self] mode in
            self?.render(mode: mode)
        }
        viewModel.onSelectionChange = { [weak self] item in
            self?.statusBarView.updateSelectedItem(item)
        }
        viewModel.onItemsChange = { [weak self] items in
            self?.gridController.update(items: items)
            self?.tableController.update(items: items)
            self?.treeController.update(items: items)
            self?.renderEmptyState(isVisible: items.isEmpty)
            self?.statusBarView.updateMatchCount(items.count)
        }
        viewModel.onSortChange = { [weak self] field, order in
            self?.toolbarView.selectSortField(field)
            self?.tableController.applySort(field: field, order: order)
            self?.treeController.applySort(field: field, order: order)
        }
        viewModel.onPreviewSizeChange = { [weak self] previewSize in
            self?.toolbarView.previewSlider.doubleValue = previewSize
            self?.applyPreviewSize(CGFloat(previewSize))
        }

        toolbarView.invisiblesButton.state = viewModel.showInvisibleItems ? .on : .off
        toolbarView.packageButton.state = viewModel.showPackageContents ? .on : .off
        toolbarView.trashedButton.state = viewModel.showTrashedItems ? .on : .off
        toolbarView.filterField.stringValue = viewModel.filterText
        toolbarView.previewSlider.doubleValue = viewModel.previewSize
        render(mode: viewModel.mode)
        applyPreviewSize(CGFloat(viewModel.previewSize))
        toolbarView.selectSortField(viewModel.sortField)
        tableController.applySort(field: viewModel.sortField, order: viewModel.sortOrder)
        treeController.applySort(field: viewModel.sortField, order: viewModel.sortOrder)
        let items = viewModel.projectedItems
        gridController.update(items: items)
        tableController.update(items: items)
        treeController.update(items: items)
        renderEmptyState(isVisible: items.isEmpty)
        statusBarView.updateMatchCount(items.count)
        statusBarView.updateSelectedItem(viewModel.selectedItem)
    }

    @objc
    private func showGridMode() {
        viewModel.mode = .grid
    }

    @objc
    private func showTableMode() {
        viewModel.mode = .table
    }

    @objc
    private func showTreeMode() {
        viewModel.mode = .tree
    }

    @objc
    private func filterChanged() {
        viewModel.filterText = toolbarView.filterField.stringValue
    }

    @objc
    private func previewSizeChanged() {
        viewModel.previewSize = toolbarView.previewSlider.doubleValue
    }

    @objc
    private func sortByChanged() {
        applySort(field: toolbarView.selectedSortField, order: .ascending)
    }

    @objc
    private func toggleInvisibles() {
        viewModel.showInvisibleItems = toolbarView.invisiblesButton.state == .on
    }

    @objc
    private func togglePackages() {
        viewModel.showPackageContents = toolbarView.packageButton.state == .on
    }

    @objc
    private func toggleTrashed() {
        viewModel.showTrashedItems = toolbarView.trashedButton.state == .on
    }

    private func render(mode: SearchResultsViewModel.Mode) {
        gridController.view.isHidden = mode != .grid
        tableController.view.isHidden = mode != .table
        treeController.view.isHidden = mode != .tree
        toolbarView.apply(mode: mode)
    }

    private func renderEmptyState(isVisible: Bool) {
        emptyStateLabel.isHidden = isVisible == false
    }

    private func updateSelection(_ items: [SearchResultItem]) {
        viewModel.selectedIDs = Set(items.map(\.id))
        viewModel.selectedItem = items.first
    }

    private func applyPreviewSize(_ previewSize: CGFloat) {
        gridController.updatePreviewSize(previewSize)
    }

    private func applySort(field: SearchResultsViewModel.SortField, order: SearchResultsViewModel.SortOrder) {
        viewModel.sortField = field
        viewModel.sortOrder = order
    }

    private func makeContextMenu(for items: [SearchResultItem]) -> NSMenu? {
        guard items.isEmpty == false else {
            return nil
        }

        menuHandlers.removeAll()
        let menu = NSMenu(title: "ResultsContextMenu")
        let state = actionController.menuState(for: items)

        menu.addItem(makeMenuItem(title: openMenuTitle(for: items)) { [weak self] in
            self?.open(items: items, applicationURL: nil)
        })

        let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        openWithItem.submenu = makeOpenWithMenu(for: items)
        menu.addItem(openWithItem)

        menu.addItem(makeMenuItem(title: "Reveal in Finder") { [weak self] in
            self?.revealInFinder(items: items)
        })
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Move to Trash", isEnabled: state.canMoveToTrash) { [weak self] in
            self?.moveToTrash(items: items)
        })
        menu.addItem(makeMenuItem(title: "Delete Immediately", isEnabled: state.canMoveToTrash) { [weak self] in
            self?.deleteImmediately(items: items)
        })
        menu.addItem(.separator())

        let copyPathItem = NSMenuItem(title: "Copy Path", action: nil, keyEquivalent: "")
        copyPathItem.submenu = makeCopyPathMenu(for: items)
        menu.addItem(copyPathItem)

        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Get Info") { [weak self] in
            self?.showInfo(items: items)
        })
        menu.addItem(makeMenuItem(title: "Rename", isEnabled: state.canRename) { [weak self] in
            self?.rename(item: items.first)
        })
        menu.addItem(makeMenuItem(title: "Create Alias in...") { [weak self] in
            self?.createAlias(items: items)
        })
        menu.addItem(makeMenuItem(title: "Quick Look") { [weak self] in
            self?.showQuickLook(items: items)
        })

        let labelItem = NSMenuItem(title: "Set Label", action: nil, keyEquivalent: "")
        labelItem.submenu = makeLabelMenu(for: items)
        menu.addItem(labelItem)

        let shouldShowAsVisible = items.allSatisfy { self.isItemHidden($0) }
        menu.addItem(makeMenuItem(title: shouldShowAsVisible ? "Make Visible" : "Make Invisible") { [weak self] in
            self?.setHidden(shouldHide: !shouldShowAsVisible, items: items)
        })
        menu.addItem(makeMenuItem(title: "Unlock") { [weak self] in
            self?.unlock(items: items)
        })
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Remove from Results", isEnabled: state.canRemoveFromResults) { [weak self] in
            guard let self else { return }
            self.actionController.removeFromResults(items: items, viewModel: self.viewModel)
        })
        menu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = makeServicesMenu()
        menu.addItem(servicesItem)

        return menu
    }

    private func openMenuTitle(for items: [SearchResultItem]) -> String {
        guard items.count == 1,
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: URL(fileURLWithPath: items[0].path)) else {
            return "Open"
        }

        let appName = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        return "Open with \(appName)"
    }

    private func makeOpenWithMenu(for items: [SearchResultItem]) -> NSMenu {
        let menu = NSMenu(title: "Open With")
        let apps = availableApplicationURLs(for: items)
        guard apps.isEmpty == false else {
            let item = NSMenuItem(title: "No Compatible Applications", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }

        for appURL in apps {
            let appName = FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
            menu.addItem(makeMenuItem(title: appName) { [weak self] in
                self?.open(items: items, applicationURL: appURL)
            })
        }
        return menu
    }

    private func makeCopyPathMenu(for items: [SearchResultItem]) -> NSMenu {
        let menu = NSMenu(title: "Copy Path")
        menu.addItem(makeMenuItem(title: "POSIX Path") {
            let value = items.map(\.path).joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        })
        menu.addItem(makeMenuItem(title: "File URL") {
            let value = items.map { URL(fileURLWithPath: $0.path).absoluteString }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        })
        return menu
    }

    private func makeLabelMenu(for items: [SearchResultItem]) -> NSMenu {
        let menu = NSMenu(title: "Set Label")
        let labels: [(String, Int)] = [
            ("None", 0),
            ("Gray", 1),
            ("Green", 2),
            ("Purple", 3),
            ("Blue", 4),
            ("Yellow", 5),
            ("Red", 6),
            ("Orange", 7)
        ]

        for (title, index) in labels {
            menu.addItem(makeMenuItem(title: title) { [weak self] in
                self?.setLabel(index: index, items: items)
            })
        }
        return menu
    }

    private func makeServicesMenu() -> NSMenu {
        let menu = NSMenu(title: "Services")
        view.window?.makeFirstResponder(self)
        NSApp.servicesMenu = menu
        NSUpdateDynamicServices()
        if menu.items.isEmpty {
            let item = NSMenuItem(title: "No Services Available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    private func makeMenuItem(title: String, isEnabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let handler = MenuActionHandler(action: action)
        menuHandlers.append(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuActionHandler.invoke), keyEquivalent: "")
        item.target = handler
        item.isEnabled = isEnabled
        return item
    }

    private func open(items: [SearchResultItem], applicationURL: URL?) {
        let urls = items.map { URL(fileURLWithPath: $0.path) }
        if let applicationURL {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration) { _, _ in }
            return
        }

        urls.forEach { NSWorkspace.shared.open($0) }
    }

    private func revealInFinder(items: [SearchResultItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map { URL(fileURLWithPath: $0.path) })
    }

    private func moveToTrash(items: [SearchResultItem]) {
        do {
            _ = try actionController.fileService.moveToTrash(urls: items.map { URL(fileURLWithPath: $0.path) })
            viewModel.removeItems(ids: Set(items.map(\.id)))
        } catch {
            presentErrorAlert(error)
        }
    }

    private func deleteImmediately(items: [SearchResultItem]) {
        do {
            try actionController.handleDeleteImmediately(items: items, viewModel: viewModel)
        } catch {
            presentErrorAlert(error)
        }
    }

    private func rename(item: SearchResultItem?) {
        guard let item else { return }

        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = item.displayName
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: item.displayName)
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try actionController.handleRename(item: item, newName: field.stringValue, viewModel: viewModel)
            } catch {
                presentErrorAlert(error)
            }
        }
    }

    private func createAlias(items: [SearchResultItem]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            for item in items {
                _ = try actionController.fileService.createAlias(for: URL(fileURLWithPath: item.path), in: destination)
            }
        } catch {
            presentErrorAlert(error)
        }
    }

    private func showQuickLook(items: [SearchResultItem]) {
        quickLookURLs = items.map { URL(fileURLWithPath: $0.path) }
        view.window?.makeFirstResponder(self)
        QLPreviewPanel.shared().reloadData()
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
    }

    private func setHidden(shouldHide: Bool, items: [SearchResultItem]) {
        let updatedItems = items.compactMap { item -> SearchResultItem? in
            do {
                let url = try actionController.fileService.setHidden(shouldHide, for: URL(fileURLWithPath: item.path))
                return refreshedItem(from: item, atPath: url.path)
            } catch {
                return nil
            }
        }
        viewModel.replaceItems(updatedItems)
    }

    private func unlock(items: [SearchResultItem]) {
        let updatedItems = items.compactMap { item -> SearchResultItem? in
            do {
                let url = try actionController.fileService.setLocked(false, for: URL(fileURLWithPath: item.path))
                return refreshedItem(from: item, atPath: url.path)
            } catch {
                return nil
            }
        }
        viewModel.replaceItems(updatedItems)
    }

    private func showInfo(items: [SearchResultItem]) {
        runFinderScript(commandBody: items.map { item in
            #"open information window of (POSIX file "\#(escapedForAppleScript(item.path))" as alias)"#
        })
    }

    private func setLabel(index: Int, items: [SearchResultItem]) {
        runFinderScript(commandBody: items.map { item in
            #"set label index of (POSIX file "\#(escapedForAppleScript(item.path))" as alias) to \#(index)"#
        })
        let updatedItems = items.compactMap { refreshedItem(from: $0, atPath: $0.path) }
        viewModel.replaceItems(updatedItems)
    }

    private func runFinderScript(commandBody: [String]) {
        let body = commandBody.joined(separator: "\n")
        let source = """
        tell application "Finder"
        \(body)
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            presentErrorAlert(NSError(domain: "FinderScript", code: 1, userInfo: error as? [String: Any]))
        }
    }

    private func refreshedItem(from item: SearchResultItem, atPath path: String) -> SearchResultItem? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let resourceValues = try? url.resourceValues(forKeys: [
            .isHiddenKey,
            .tagNamesKey,
            .isApplicationKey,
            .creationDateKey,
            .contentAccessDateKey,
            .addedToDirectoryDateKey
        ])
        return SearchResultItem(
            id: item.id,
            path: path,
            matchReason: item.matchReason,
            previewSnippet: item.previewSnippet,
            highlightKind: item.highlightKind,
            highlightQuery: item.highlightQuery,
            kind: item.kind,
            modifiedText: displayModifiedDate(attributes: attributes),
            createdText: displayDate((attributes[.creationDate] as? Date) ?? resourceValues?.creationDate),
            lastOpenedText: displayDate(resourceValues?.contentAccessDate),
            addedText: displayDate(resourceValues?.addedToDirectoryDate),
            sizeText: displaySize(attributes: attributes),
            tagsText: resourceValues?.tagNames?.joined(separator: ", ") ?? item.tagsText,
            enclosingFolder: url.deletingLastPathComponent().path,
            isInvisible: resourceValues?.isHidden == true,
            isPackage: resourceValues?.isApplication == true || item.isPackage,
            isTrashed: item.isTrashed,
            modifiedDate: attributes[.modificationDate] as? Date,
            createdDate: (attributes[.creationDate] as? Date) ?? resourceValues?.creationDate,
            lastOpenedDate: resourceValues?.contentAccessDate,
            addedDate: resourceValues?.addedToDirectoryDate,
            sizeBytes: (attributes[.size] as? NSNumber)?.int64Value,
            tags: resourceValues?.tagNames ?? item.tags
        )
    }

    private func availableApplicationURLs(for items: [SearchResultItem]) -> [URL] {
        let itemURLs = items.map { URL(fileURLWithPath: $0.path) }
        guard let first = itemURLs.first else {
            return []
        }

        var available = Set(applicationURLs(for: first).map(\.path))
        for url in itemURLs.dropFirst() {
            available.formIntersection(applicationURLs(for: url).map(\.path))
        }

        return available.map { URL(fileURLWithPath: $0) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func applicationURLs(for url: URL) -> [URL] {
        if #available(macOS 12.0, *) {
            return NSWorkspace.shared.urlsForApplications(toOpen: url)
        }

        let unmanaged = LSCopyApplicationURLsForURL(url as CFURL, LSRolesMask.all)
        return unmanaged?.takeRetainedValue() as? [URL] ?? []
    }

    private func isItemHidden(_ item: SearchResultItem) -> Bool {
        let values = try? URL(fileURLWithPath: item.path).resourceValues(forKeys: [.isHiddenKey])
        return values?.isHidden ?? item.isInvisible
    }

    private func displayModifiedDate(attributes: [FileAttributeKey: Any]) -> String {
        displayDate(attributes[.modificationDate] as? Date)
    }

    private func displayDate(_ date: Date?) -> String {
        guard let date else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
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

    private func presentErrorAlert(_ error: Error) {
        let alert = NSAlert(error: error as NSError)
        alert.runModal()
    }

    private func escapedForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func confirm(request: ResultConfirmationRequest) -> Bool {
        switch request {
        case .deleteImmediately(let itemCount):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Delete Immediately?"
            alert.informativeText = itemCount == 1
                ? "This item will be deleted permanently."
                : "\(itemCount) items will be deleted permanently."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        let selectedURLs = viewModel.selectedItems.map { URL(fileURLWithPath: $0.path) }
        guard selectedURLs.isEmpty == false else {
            return super.validRequestor(forSendType: sendType, returnType: returnType)
        }

        if sendType == nil || sendType == .fileURL || sendType == .string {
            return self
        }

        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc
    func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let selectedURLs = viewModel.selectedItems.map { URL(fileURLWithPath: $0.path) }
        guard selectedURLs.isEmpty == false else {
            return false
        }

        pasteboard.clearContents()
        if types.contains(.fileURL) {
            return pasteboard.writeObjects(selectedURLs as [NSURL])
        }

        if types.contains(.string) {
            pasteboard.setString(selectedURLs.map(\.path).joined(separator: "\n"), forType: .string)
            return true
        }

        return false
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        quickLookURLs[index] as NSURL
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

#if DEBUG
extension SearchResultsViewController {
    var debugShowsEmptyState: Bool {
        emptyStateLabel.isHidden == false
    }

    var debugSelectedMode: SearchResultsViewModel.Mode? {
        if toolbarView.gridButton.state == .on {
            return .grid
        }
        if toolbarView.tableButton.state == .on {
            return .table
        }
        if toolbarView.treeButton.state == .on {
            return .tree
        }
        return nil
    }

    var debugShowsPreviewSlider: Bool {
        toolbarView.previewSlider.isHidden == false
    }

    var debugShowsSortPopup: Bool {
        toolbarView.sortByPopup.isHidden == false
    }

    var debugGridItemSize: NSSize {
        gridController.debugItemSize
    }

    func debugSetPreviewSize(_ value: Double) {
        toolbarView.previewSlider.doubleValue = value
        previewSizeChanged()
    }

    var debugMatchCountValue: Int {
        statusBarView.matchCountValue
    }

    var debugSelectedPathComponents: [String] {
        statusBarView.displayedPathComponents
    }

    var debugToolbarTooltips: [String] {
        [
            toolbarView.gridButton.toolTip,
            toolbarView.tableButton.toolTip,
            toolbarView.treeButton.toolTip,
            toolbarView.invisiblesButton.toolTip,
            toolbarView.packageButton.toolTip,
            toolbarView.trashedButton.toolTip
        ].compactMap { $0 }
    }

    func debugToggleInvisibles() {
        toolbarView.invisiblesButton.performClick(nil)
    }

    func debugTogglePackages() {
        toolbarView.packageButton.performClick(nil)
    }

    func debugToggleTrashed() {
        toolbarView.trashedButton.performClick(nil)
    }

    var debugSortTitles: [String] {
        toolbarView.sortByPopup.itemTitles
    }
}
#endif

private final class MenuActionHandler: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc
    func invoke() {
        action()
    }
}

private final class ResultsStatusBarView: NSView {
    private let pathStackView = NSStackView()
    private let countLabel = NSTextField(labelWithString: "")
    private var buttonHandlers: [MenuActionHandler] = []

    private(set) var displayedPathComponents: [String] = []
    private(set) var matchCountValue = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        let borderLayer = CALayer()
        borderLayer.backgroundColor = NSColor.separatorColor.cgColor
        layer?.addSublayer(borderLayer)

        pathStackView.orientation = .horizontal
        pathStackView.alignment = .centerY
        pathStackView.spacing = 4
        pathStackView.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right

        addSubview(pathStackView)
        addSubview(countLabel)

        pathStackView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.trailing.lessThanOrEqualTo(countLabel.snp.leading).offset(-12)
        }
        countLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
            make.leading.greaterThanOrEqualTo(pathStackView.snp.trailing).offset(12)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard let borderLayer = layer?.sublayers?.first else {
            return
        }
        borderLayer.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }

    func updateMatchCount(_ count: Int) {
        matchCountValue = count
        countLabel.stringValue = String.localizedStringWithFormat(
            NSLocalizedString("results.status.matched", comment: ""),
            count
        )
    }

    func updateSelectedItem(_ item: SearchResultItem?) {
        buttonHandlers.removeAll()
        displayedPathComponents = []
        pathStackView.arrangedSubviews.forEach {
            pathStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        guard let item else {
            pathStackView.isHidden = true
            return
        }

        pathStackView.isHidden = false
        let segments = breadcrumbSegments(for: item.path)
        displayedPathComponents = segments.map(\.title)

        for (index, segment) in segments.enumerated() {
            let button = ResultsPathComponentButton(title: segment.title)
            let handler = MenuActionHandler { [path = segment.path] in
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            button.target = handler
            button.action = #selector(MenuActionHandler.invoke)
            buttonHandlers.append(handler)
            pathStackView.addArrangedSubview(button)

            if index < segments.count - 1 {
                let separator = NSTextField(labelWithString: "/")
                separator.font = .systemFont(ofSize: 11, weight: .medium)
                separator.textColor = .tertiaryLabelColor
                pathStackView.addArrangedSubview(separator)
            }
        }
    }

    private func breadcrumbSegments(for path: String) -> [(title: String, path: String)] {
        let components = URL(fileURLWithPath: path).pathComponents.filter { $0 != "/" }
        var currentPath = ""
        return components.map { component in
            currentPath += "/\(component)"
            return (title: component, path: currentPath)
        }
    }
}

private final class ResultsPathComponentButton: NSButton {
    private let fadeView = ResultsFadeView()
    private var isHovered = false
    private var trackingAreaReference: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .inline
        imagePosition = .noImage
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 4
        toolTip = title
        cell?.lineBreakMode = .byTruncatingTail
        addSubview(fadeView)
        fadeView.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview()
            make.width.equalTo(18)
        }
        snp.makeConstraints { make in
            make.width.lessThanOrEqualTo(120)
        }
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let trackingAreaReference = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaReference)
        self.trackingAreaReference = trackingAreaReference
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        super.mouseExited(with: event)
    }

    override func layout() {
        super.layout()
        fadeView.isHidden = intrinsicContentSize.width <= bounds.width || isHovered
    }

    private func updateAppearance() {
        let color: NSColor = isHovered ? .controlAccentColor : .secondaryLabelColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: isHovered ? .semibold : .regular),
                .foregroundColor: color
            ]
        )
        layer?.backgroundColor = isHovered ? NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
    }
}

private final class ResultsFadeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let gradientLayer: CAGradientLayer
        if let existing = layer as? CAGradientLayer {
            gradientLayer = existing
        } else {
            gradientLayer = CAGradientLayer()
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.colors = [
                NSColor.windowBackgroundColor.withAlphaComponent(0).cgColor,
                NSColor.windowBackgroundColor.cgColor
            ]
            self.layer = gradientLayer
        }
        gradientLayer.frame = bounds
    }
}

struct SearchResultNameHighlighter {
    static func attributedTitle(for item: SearchResultItem, baseColor: NSColor) -> NSAttributedString {
        let title = item.displayName
        let attributed = NSMutableAttributedString(
            string: title,
            attributes: [
                .foregroundColor: baseColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
        )

        for range in highlightRanges(for: item, title: title) {
            attributed.addAttributes(
                [
                    .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.28),
                    .foregroundColor: baseColor
                ],
                range: range
            )
        }

        return attributed
    }

    private static func highlightRanges(for item: SearchResultItem, title: String) -> [NSRange] {
        guard let kind = item.highlightKind,
              let query = item.highlightQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
              query.isEmpty == false else {
            return []
        }

        let searchTerms = query
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { $0.isEmpty == false }
        guard searchTerms.isEmpty == false else {
            return []
        }

        let candidateRange: Range<String.Index>
        switch kind {
        case .name:
            candidateRange = title.startIndex..<title.endIndex
        case .extensionName:
            guard let dotIndex = title.lastIndex(of: ".") else {
                return []
            }
            candidateRange = dotIndex..<title.endIndex
        }

        return searchTerms.compactMap { term in
            let normalized = kind == .extensionName ? term.trimmingCharacters(in: CharacterSet(charactersIn: ".")) : term
            guard normalized.isEmpty == false else {
                return nil
            }

            let scopedTitle = String(title[candidateRange])
            guard let range = scopedTitle.range(of: normalized, options: [.caseInsensitive, .diacriticInsensitive]) else {
                return nil
            }

            let lowerOffset = scopedTitle.distance(from: scopedTitle.startIndex, to: range.lowerBound)
            let location = title.distance(from: title.startIndex, to: candidateRange.lowerBound) + lowerOffset
            return NSRange(location: location, length: scopedTitle.distance(from: range.lowerBound, to: range.upperBound))
        }
    }
}
