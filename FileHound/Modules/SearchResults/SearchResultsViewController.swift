import AppKit
import SnapKit

final class SearchResultsViewController: NSViewController {
    private let viewModel: SearchResultsViewModel
    private let listController = ResultsTableViewController()
    private let treeController = ResultsOutlineViewController()
    private let containerView = NSView()
    private let listButton = NSButton(title: L10n.string("results.mode.list"), target: nil, action: nil)
    private let treeButton = NSButton(title: L10n.string("results.mode.tree"), target: nil, action: nil)

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

        listButton.target = self
        listButton.action = #selector(showListMode)
        treeButton.target = self
        treeButton.action = #selector(showTreeMode)

        let buttonStack = NSStackView(views: [listButton, treeButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        addChild(listController)
        addChild(treeController)
        containerView.addSubview(listController.view)
        containerView.addSubview(treeController.view)

        rootView.addSubview(buttonStack)
        rootView.addSubview(containerView)

        buttonStack.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(20)
        }
        containerView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(20)
            make.top.equalTo(buttonStack.snp.bottom).offset(12)
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

    private func render(mode: SearchResultsViewModel.Mode) {
        listController.view.isHidden = mode != .list
        treeController.view.isHidden = mode != .tree
    }
}
