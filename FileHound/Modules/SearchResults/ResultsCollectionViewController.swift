import AppKit
import SnapKit

final class ResultsCollectionViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private let collectionView = ContextMenuCollectionView()
    private let scrollView = NSScrollView()
    private let layout = NSCollectionViewFlowLayout()
    private var items: [SearchResultItem] = []
    private let iconProvider = ResultIconProvider()
    private var previewSize: CGFloat = 72

    var onSelectionChange: ((SearchResultItem?) -> Void)?
    var onSelectionSetChange: (([SearchResultItem]) -> Void)?
    var contextMenuProvider: (([SearchResultItem]) -> NSMenu?)?
    var onOpenItems: (([SearchResultItem]) -> Void)?
    var onQuickLookRequest: (([SearchResultItem]) -> Void)?

    override func loadView() {
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

        applyPreviewLayout()

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        view = scrollView
    }

    func update(items: [SearchResultItem]) {
        self.items = items
        collectionView.reloadData()
    }

    func updatePreviewSize(_ previewSize: CGFloat) {
        self.previewSize = max(32, min(previewSize, 128))
        applyPreviewLayout()
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

        resultItem.render(items[indexPath.item], iconProvider: iconProvider, previewSize: previewSize)
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

    private func applyPreviewLayout() {
        let iconSize = previewSize
        layout.itemSize = NSSize(width: iconSize + 60, height: iconSize + 44)
        layout.minimumInteritemSpacing = max(14, floor(iconSize / 4))
        layout.minimumLineSpacing = max(14, floor(iconSize / 4))
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }
}

private final class ResultGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ResultGridItem")

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let selectionOverlay = NSView()
    private var representedPath: String?
    private var iconSizeConstraint: Constraint?
    private var currentItem: SearchResultItem?

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
            iconSizeConstraint = make.size.equalTo(72).constraint
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
            applyHighlightedTitle()
        }
    }

    func render(_ item: SearchResultItem, iconProvider: ResultIconProvider, previewSize: CGFloat) {
        currentItem = item
        representedPath = item.path
        iconSizeConstraint?.update(offset: previewSize)
        iconView.image = NSWorkspace.shared.icon(forFile: item.path)
        titleLabel.setAccessibilityIdentifier(item.displayName)
        applyHighlightedTitle()

        let path = item.path
        Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await iconProvider.icon(
                for: URL(fileURLWithPath: path),
                size: NSSize(width: previewSize, height: previewSize),
                preferThumbnail: true
            )
            guard self.representedPath == path else { return }
            self.iconView.image = image
        }
    }

    private func applyHighlightedTitle() {
        guard let currentItem else {
            return
        }
        titleLabel.attributedStringValue = centeredGridTitle(
            for: currentItem,
            baseColor: isSelected ? .controlAccentColor : .labelColor
        )
    }

    private func centeredGridTitle(for item: SearchResultItem, baseColor: NSColor) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            attributedString: SearchResultNameHighlighter.attributedTitle(for: item, baseColor: baseColor)
        )
        guard attributed.length > 0 else {
            return attributed
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingMiddle
        attributed.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: attributed.length)
        )
        return attributed
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

#if DEBUG
private extension ResultGridItem {
    var debugTitleParagraphAlignment: NSTextAlignment {
        guard titleLabel.attributedStringValue.length > 0,
              let style = titleLabel.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle else {
            return .left
        }
        return style.alignment
    }

    var debugTitleMaximumNumberOfLines: Int {
        titleLabel.maximumNumberOfLines
    }

    var debugTitleLineBreakMode: NSLineBreakMode {
        titleLabel.lineBreakMode
    }

    var debugTitleAlignmentOffset: CGFloat {
        let iconRect = iconView.convert(iconView.bounds, to: view)
        let labelRect = titleLabel.convert(titleLabel.bounds, to: view)
        let measured = titleLabel.attributedStringValue.boundingRect(
            with: NSSize(width: labelRect.width, height: labelRect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textWidth = min(labelRect.width, ceil(measured.width))
        let textMidX: CGFloat

        switch debugTitleParagraphAlignment {
        case .center:
            textMidX = labelRect.minX + floor((labelRect.width - textWidth) / 2) + (textWidth / 2)
        case .right:
            textMidX = labelRect.maxX - (textWidth / 2)
        default:
            textMidX = labelRect.minX + (textWidth / 2)
        }

        return abs(iconRect.midX - textMidX)
    }
}

extension ResultsCollectionViewController {
    var debugItemSize: NSSize {
        layout.itemSize
    }

    private func debugGridItem(for item: SearchResultItem, previewSize: CGFloat) -> ResultGridItem {
        let gridItem = ResultGridItem()
        _ = gridItem.view
        gridItem.view.frame = NSRect(x: 0, y: 0, width: previewSize + 60, height: previewSize + 44)
        gridItem.render(item, iconProvider: iconProvider, previewSize: previewSize)
        gridItem.view.layoutSubtreeIfNeeded()
        return gridItem
    }

    func debugTitleAlignmentOffset(for item: SearchResultItem, previewSize: CGFloat) -> CGFloat {
        debugGridItem(for: item, previewSize: previewSize).debugTitleAlignmentOffset
    }

    func debugTitleParagraphAlignment(for item: SearchResultItem, previewSize: CGFloat) -> NSTextAlignment {
        debugGridItem(for: item, previewSize: previewSize).debugTitleParagraphAlignment
    }

    var debugTitleMaximumNumberOfLines: Int {
        let gridItem = ResultGridItem()
        _ = gridItem.view
        return gridItem.debugTitleMaximumNumberOfLines
    }

    var debugTitleLineBreakMode: NSLineBreakMode {
        let gridItem = ResultGridItem()
        _ = gridItem.view
        return gridItem.debugTitleLineBreakMode
    }
}
#endif
