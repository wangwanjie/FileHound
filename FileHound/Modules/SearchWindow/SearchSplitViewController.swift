//
//  SearchSplitViewController.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit
import SnapKit

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
        let leftPane = NSView()
        let rightPane = NSView()
        let divider = NSBox()
        divider.boxType = .separator

        addChild(rulesController)
        addChild(resultsController)
        addChild(previewController)

        leftPane.addSubview(rulesController.view)
        leftPane.addSubview(resultsController.view)
        rightPane.addSubview(previewController.view)
        rootView.addSubview(leftPane)
        rootView.addSubview(divider)
        rootView.addSubview(rightPane)

        leftPane.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
        }
        divider.snp.makeConstraints { make in
            make.leading.equalTo(leftPane.snp.trailing)
            make.width.equalTo(1)
            make.top.bottom.equalToSuperview()
        }
        rightPane.snp.makeConstraints { make in
            make.leading.equalTo(divider.snp.trailing)
            make.trailing.top.bottom.equalToSuperview()
            make.width.equalTo(260)
        }

        rulesController.view.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(100)
        }
        resultsController.view.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(rulesController.view.snp.bottom).offset(12)
        }
        previewController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        view = rootView
    }
}
