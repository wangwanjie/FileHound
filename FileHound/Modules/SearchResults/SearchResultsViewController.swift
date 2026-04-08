import AppKit
import SnapKit

final class SearchResultsViewController: NSViewController {
    private let viewModel: SearchResultsViewModel
    private let listController = ResultsTableViewController()
    private let treeController = ResultsOutlineViewController()
    private let containerView = NSView()
    private let listButton = NSButton(title: "", target: nil, action: nil)
    private let treeButton = NSButton(title: "", target: nil, action: nil)
    private let invisiblesButton = NSButton(title: "Invisibles", target: nil, action: nil)
    private let packageButton = NSButton(title: "Package Contents", target: nil, action: nil)
    private let trashedButton = NSButton(title: "Trashed", target: nil, action: nil)
    private let filterField = NSSearchField()

    init(viewModel: SearchResultsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView()

        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1).cgColor

        listButton.target = self
        listButton.action = #selector(showListMode)
        treeButton.target = self
        treeButton.action = #selector(showTreeMode)
        listButton.title = "☷"
        treeButton.title = "☰"
        listButton.setAccessibilityIdentifier("列表视图")
        treeButton.setAccessibilityIdentifier("树形视图")

        [invisiblesButton, packageButton, trashedButton].forEach { button in
            button.setButtonType(.toggle)
            button.bezelStyle = .texturedRounded
        }

        filterField.placeholderString = "Filter"
        filterField.target = self
        filterField.action = #selector(filterChanged)

        let leftStack = NSStackView(views: [listButton, treeButton, invisiblesButton, packageButton, trashedButton])
        leftStack.orientation = .horizontal
        leftStack.spacing = 10

        addChild(listController)
        addChild(treeController)
        containerView.addSubview(listController.view)
        containerView.addSubview(treeController.view)

        rootView.addSubview(leftStack)
        rootView.addSubview(filterField)
        rootView.addSubview(containerView)

        leftStack.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(12)
        }
        filterField.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(12)
            make.centerY.equalTo(leftStack)
            make.width.equalTo(220)
        }
        containerView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(12)
            make.top.equalTo(leftStack.snp.bottom).offset(12)
        }
        listController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        treeController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        listController.onSelectionChange = { [weak self] item in
            self?.viewModel.selectedItem = item
        }
        treeController.onSelectionChange = { [weak self] item in
            self?.viewModel.selectedItem = item
        }

        viewModel.onModeChange = { [weak self] mode in
            self?.render(mode: mode)
        }
        viewModel.onItemsChange = { [weak self] items in
            self?.listController.update(items: items)
            self?.treeController.update(items: items)
        }
        viewModel.onFilterChange = { [weak self] text in
            self?.listController.applyFilter(text)
            self?.treeController.applyFilter(text)
        }

        render(mode: viewModel.mode)
        listController.update(items: viewModel.items)
        treeController.update(items: viewModel.items)
    }

    @objc
    private func showListMode() {
        viewModel.mode = .list
    }

    @objc
    private func showTreeMode() {
        viewModel.mode = .tree
    }

    @objc
    private func filterChanged() {
        viewModel.filterText = filterField.stringValue
    }

    private func render(mode: SearchResultsViewModel.Mode) {
        listController.view.isHidden = mode != .list
        treeController.view.isHidden = mode != .tree
    }
}
