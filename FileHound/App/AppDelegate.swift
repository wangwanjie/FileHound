//
//  AppDelegate.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: SearchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder().build()

        let controller = SearchWindowController()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        windowController = controller
    }
}
