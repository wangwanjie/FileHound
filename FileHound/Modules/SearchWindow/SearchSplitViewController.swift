//
//  SearchSplitViewController.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit

final class SearchSplitViewController: NSSplitViewController {
    private let viewModel = SearchResultsViewModel()
    private let previewController = PreviewPanelViewController()

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebar = SavedSearchSidebarViewController()
        let workspace = WorkspaceContentViewController(
            rulesController: SearchRulesViewController(),
            resultsController: SearchResultsViewController(viewModel: viewModel),
            previewController: previewController
        )

        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 200

        let workspaceItem = NSSplitViewItem(viewController: workspace)

        addSplitViewItem(sidebarItem)
        addSplitViewItem(workspaceItem)

        viewModel.onSelectionChange = { [weak self] item in
            self?.previewController.render(item)
        }
        seedFixtureResultsIfNeeded()
    }

    private func seedFixtureResultsIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--fixture-results") else {
            return
        }

        viewModel.items = [
            SearchResultItem(
                id: UUID(),
                path: "/tmp/report.txt",
                matchReason: "内容命中",
                previewSnippet: "demo"
            )
        ]
    }
}

private final class WorkspaceContentViewController: NSViewController {
    private let rulesController: SearchRulesViewController
    private let resultsController: SearchResultsViewController
    private let previewController: PreviewPanelViewController

    init(
        rulesController: SearchRulesViewController,
        resultsController: SearchResultsViewController,
        previewController: PreviewPanelViewController
    ) {
        self.rulesController = rulesController
        self.resultsController = resultsController
        self.previewController = previewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView()
        let horizontalSplit = NSSplitView()
        horizontalSplit.isVertical = true
        horizontalSplit.dividerStyle = .thin
        horizontalSplit.translatesAutoresizingMaskIntoConstraints = false

        let leftStack = NSStackView()
        leftStack.orientation = .vertical
        leftStack.spacing = 12
        leftStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        addChild(rulesController)
        addChild(resultsController)
        addChild(previewController)

        rulesController.view.translatesAutoresizingMaskIntoConstraints = false
        resultsController.view.translatesAutoresizingMaskIntoConstraints = false
        previewController.view.translatesAutoresizingMaskIntoConstraints = false

        leftStack.addArrangedSubview(rulesController.view)
        leftStack.addArrangedSubview(resultsController.view)
        rulesController.view.heightAnchor.constraint(equalToConstant: 100).isActive = true

        let leftPane = NSView()
        leftPane.addSubview(leftStack)

        let rightPane = NSView()
        rightPane.addSubview(previewController.view)

        horizontalSplit.addArrangedSubview(leftPane)
        horizontalSplit.addArrangedSubview(rightPane)

        rootView.addSubview(horizontalSplit)

        NSLayoutConstraint.activate([
            horizontalSplit.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            horizontalSplit.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            horizontalSplit.topAnchor.constraint(equalTo: rootView.topAnchor),
            horizontalSplit.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            leftStack.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            leftStack.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            leftStack.topAnchor.constraint(equalTo: leftPane.topAnchor),
            leftStack.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            previewController.view.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            previewController.view.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            previewController.view.topAnchor.constraint(equalTo: rightPane.topAnchor),
            previewController.view.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor),

            rightPane.widthAnchor.constraint(equalToConstant: 260)
        ])

        view = rootView
    }
}
