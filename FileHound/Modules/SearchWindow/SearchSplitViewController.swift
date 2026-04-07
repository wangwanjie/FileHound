//
//  SearchSplitViewController.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit

final class SearchSplitViewController: NSSplitViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebar = makePlaceholder(title: "Sidebar")
        let workspace = makePlaceholder(title: "Workspace")

        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 200

        let workspaceItem = NSSplitViewItem(viewController: workspace)

        addSplitViewItem(sidebarItem)
        addSplitViewItem(workspaceItem)
    }

    private func makePlaceholder(title: String) -> NSViewController {
        let controller = NSViewController()
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        controller.view = container
        return controller
    }
}
