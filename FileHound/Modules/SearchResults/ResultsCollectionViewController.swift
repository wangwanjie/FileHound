import AppKit
import SnapKit

final class ResultsCollectionViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private let collectionView = ContextMenuCollectionView()
    private let scrollView = NSScrollView()
    private var items: [SearchResultItem] = []
    private let iconProvider = ResultIconProvider()

    var onSelectionChange: ((SearchResultItem?) -> Void)?
    var onSelectionSetChange: (([SearchResultItem]) -> Void)?
    var contextMenuProvider: (([SearchResultItem]) -> NSMenu?)?
    var onOpenItems: (([SearchResultItem]) -> Void)?
    var onQuickLookRequest: (([SearchResultItem]) -> Void)?

    override func loadView() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 132, height: 116)
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 16

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.register(ResultGridItem.self, forItemWithIdentifier: ResultGridItem.identifier)
        collectionView.setAccessibilityIdentifier("ResultsGrid")
        collectionView.menuProvider = { [weak self] event in
            self?.menu(for: event)
        }
        collectionView.doubleClickHandler = { [weak self] in
            self?.doubleClicked()
        }
        collectionView.quickLookHandler = { [weak self] in
            self?.quickLookRequested()
        }

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        view = scrollView
    }

    func update(items: [SearchResultItem]) {
        self.items = items
        collectionView.reloadData()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ResultGridItem.identifier, for: indexPath)
        guard let resultItem = item as? ResultGridItem else {
            return item
        }

        resultItem.render(items[indexPath.item], iconProvider: iconProvider)
        return resultItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        notifySelectionChange()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        notifySelectionChange()
    }

    @objc
    private func doubleClicked() {
        let selected = selectedItems()
        guard selected.isEmpty == false else {
            return
        }
        onOpenItems?(selected)
    }

    private func quickLookRequested() {
        let selected = selectedItems()
        guard selected.isEmpty == false else {
            return
        }
        onQuickLookRequest?(selected)
    }

    private func menu(for event: NSEvent) -> NSMenu? {
        let point = collectionView.convert(event.locationInWindow, from: nil)
        if let indexPath = collectionView.indexPathForItem(at: point),
           collectionView.selectionIndexPaths.contains(indexPath) == false {
            collectionView.selectionIndexPaths = [indexPath]
            notifySelectionChange()
        }

        let selected = selectedItems()
        return selected.isEmpty ? nil : contextMenuProvider?(selected)
    }

    private func selectedItems() -> [SearchResultItem] {
        collectionView.selectionIndexPaths
            .sorted { $0.item < $1.item }
            .compactMap { indexPath in
                items.indices.contains(indexPath.item) ? items[indexPath.item] : nil
            }
    }

    private func notifySelectionChange() {
        let selected = selectedItems()
        onSelectionSetChange?(selected)
        onSelectionChange?(selected.first)
    }
}

private final class ResultGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ResultGridItem")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let selectionOverlay = NSView()
    private var representedPath: String?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.clear.cgColor
        view.layer?.backgroundColor = NSColor.clear.cgColor

        selectionOverlay.wantsLayer = true
        selectionOverlay.layer?.cornerRadius = 10
        selectionOverlay.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        selectionOverlay.isHidden = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingMiddle

        view.addSubview(selectionOverlay)
        view.addSubview(iconView)
        view.addSubview(titleLabel)
        selectionOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        iconView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(10)
            make.centerX.equalToSuperview()
            make.size.equalTo(72)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(8)
            make.top.equalTo(iconView.snp.bottom).offset(10)
        }
    }

    override var isSelected: Bool {
        didSet {
            selectionOverlay.isHidden = isSelected == false
            view.layer?.borderColor = isSelected
                ? NSColor.controlAccentColor.cgColor
                : NSColor.clear.cgColor
            titleLabel.textColor = isSelected ? .controlAccentColor : .labelColor
        }
    }

    func render(_ item: SearchResultItem, iconProvider: ResultIconProvider) {
        representedPath = item.path
        iconView.image = NSWorkspace.shared.icon(forFile: item.path)
        titleLabel.stringValue = item.displayName
        titleLabel.setAccessibilityIdentifier(item.displayName)

        let path = item.path
        Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await iconProvider.icon(
                for: URL(fileURLWithPath: path),
                size: NSSize(width: 72, height: 72),
                preferThumbnail: true
            )
            guard self.representedPath == path else { return }
            self.iconView.image = image
        }
    }
}

private final class ContextMenuCollectionView: NSCollectionView {
    var menuProvider: ((NSEvent) -> NSMenu?)?
    var doubleClickHandler: (() -> Void)?
    var quickLookHandler: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if event.clickCount == 2 {
            doubleClickHandler?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            quickLookHandler?()
            return
        }
        super.keyDown(with: event)
    }
}
