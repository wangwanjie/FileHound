//
//  AppDelegate.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: SearchWindowController?
    private lazy var preferencesWindowController = PreferencesWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder(target: self).build()

        let controller = SearchWindowController()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        windowController = controller
    }

    @objc
    func openPreferences(_ sender: Any?) {
        preferencesWindowController.showWindow(sender)
        preferencesWindowController.window?.makeKeyAndOrderFront(sender)
    }
}
