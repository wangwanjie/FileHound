import AppKit
import SnapKit

final class ResultsCollectionViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private let collectionView = NSCollectionView()
    private let scrollView = NSScrollView()
    private var items: [SearchResultItem] = []

    var onSelectionChange: ((SearchResultItem?) -> Void)?

    override func loadView() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 150, height: 90)
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 16

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.register(ResultGridItem.self, forItemWithIdentifier: ResultGridItem.identifier)
        collectionView.setAccessibilityIdentifier("ResultsGrid")

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

        resultItem.render(items[indexPath.item])
        return resultItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first else {
            onSelectionChange?(nil)
            return
        }
        onSelectionChange?(items[indexPath.item])
    }
}

private final class ResultGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ResultGridItem")

    private let titleLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 10

        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle

        view.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(8)
        }
    }

    func render(_ item: SearchResultItem) {
        titleLabel.stringValue = item.displayName
        titleLabel.setAccessibilityIdentifier(item.displayName)
    }
}
