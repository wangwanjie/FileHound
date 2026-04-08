//
//  SearchWindowController.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit

final class SearchWindowController: NSWindowController {
    convenience init() {
        let splitController = SearchSplitViewController()
        let window = NSWindow(contentViewController: splitController)
        window.title = "Find Any File"
        window.setContentSize(NSSize(width: 1140, height: 300))
        window.center()
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}
