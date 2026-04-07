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
        window.title = "FileHound"
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.center()
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}
