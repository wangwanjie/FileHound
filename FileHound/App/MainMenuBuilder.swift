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

        let editMenuItem = NSMenuItem(title: L10n.string("menu.edit"), action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: L10n.string("menu.edit"))
        editMenu.addItem(withTitle: L10n.string("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.string("menu.redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.string("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.string("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.string("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.string("menu.select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        return mainMenu
    }
}
