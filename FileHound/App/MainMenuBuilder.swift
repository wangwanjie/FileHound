//
//  MainMenuBuilder.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit

final class MainMenuBuilder {
    private weak var target: AnyObject?

    init(target: AnyObject? = nil) {
        self.target = target
    }

    func build() -> NSMenu {
        let mainMenu = NSMenu(title: "MainMenu")

        let appMenuItem = NSMenuItem(title: "FileHound", action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "FileHound")
        let aboutItem = NSMenuItem(
            title: L10n.string("menu.about"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let preferencesItem = NSMenuItem(
            title: L10n.string("menu.preferences"),
            action: #selector(AppDelegate.openPreferences(_:)),
            keyEquivalent: ","
        )
        preferencesItem.target = target
        appMenu.addItem(preferencesItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.string("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        return mainMenu
    }
}
