import AppKit

final class SearchResultsViewController: NSViewController {
    private let viewModel: SearchResultsViewModel
    private let listController = ResultsTableViewController()
    private let treeController = ResultsOutlineViewController()
    private let containerView = NSView()
    private let listButton = NSButton(title: "列表视图", target: nil, action: nil)
    private let treeButton = NSButton(title: "树形视图", target: nil, action: nil)

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
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        containerView.translatesAutoresizingMaskIntoConstraints = false

        addChild(listController)
        addChild(treeController)
        listController.view.translatesAutoresizingMaskIntoConstraints = false
        treeController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(listController.view)
        containerView.addSubview(treeController.view)

        rootView.addSubview(buttonStack)
        rootView.addSubview(containerView)

        NSLayoutConstraint.activate([
            buttonStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            buttonStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 16),

            containerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            containerView.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 12),
            containerView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -16),

            listController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            listController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            listController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            listController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            treeController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            treeController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            treeController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            treeController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

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
