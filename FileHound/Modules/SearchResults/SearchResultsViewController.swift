import AppKit
import SnapKit

final class SearchResultsViewController: NSViewController {
    private let viewModel: SearchResultsViewModel
    private let gridController = ResultsCollectionViewController()
    private let tableController = ResultsTableViewController()
    private let treeController = ResultsOutlineViewController()
    private let toolbarView = ResultsToolbarView()
    private let containerView = NSView()

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

        addChild(gridController)
        addChild(tableController)
        addChild(treeController)
        containerView.addSubview(gridController.view)
        containerView.addSubview(tableController.view)
        containerView.addSubview(treeController.view)

        toolbarView.gridButton.target = self
        toolbarView.gridButton.action = #selector(showGridMode)
        toolbarView.tableButton.target = self
        toolbarView.tableButton.action = #selector(showTableMode)
        toolbarView.treeButton.target = self
        toolbarView.treeButton.action = #selector(showTreeMode)
        toolbarView.filterField.target = self
        toolbarView.filterField.action = #selector(filterChanged)
        toolbarView.invisiblesButton.target = self
        toolbarView.invisiblesButton.action = #selector(toggleInvisibles)
        toolbarView.packageButton.target = self
        toolbarView.packageButton.action = #selector(togglePackages)
        toolbarView.trashedButton.target = self
        toolbarView.trashedButton.action = #selector(toggleTrashed)

        rootView.addSubview(toolbarView)
        rootView.addSubview(containerView)

        toolbarView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
        }
        containerView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(12)
            make.top.equalTo(toolbarView.snp.bottom)
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

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        gridController.onSelectionChange = { [weak self] item in
            self?.viewModel.selectedItem = item
        }
        tableController.onSelectionChange = { [weak self] item in
            self?.viewModel.selectedItem = item
        }
        treeController.onSelectionChange = { [weak self] item in
            self?.viewModel.selectedItem = item
        }

        viewModel.onModeChange = { [weak self] mode in
            self?.render(mode: mode)
        }
        viewModel.onItemsChange = { [weak self] items in
            self?.gridController.update(items: items)
            self?.tableController.update(items: items)
            self?.treeController.update(items: items)
        }

        render(mode: viewModel.mode)
        let items = viewModel.projectedItems
        gridController.update(items: items)
        tableController.update(items: items)
        treeController.update(items: items)
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
    }
}
