//
//  MainMenuBuilder.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit

final class MainMenuBuilder {
    private weak var target: AnyObject?
    private let settings: AppSettings
    private let searchHistoryStore: SearchHistoryStore
    private let savedSearchStore: SavedSearchStore

    init(
        target: AnyObject? = nil,
        settings: AppSettings = .shared,
        searchHistoryStore: SearchHistoryStore = .shared,
        savedSearchStore: SavedSearchStore = .shared
    ) {
        self.target = target
        self.settings = settings
        self.searchHistoryStore = searchHistoryStore
        self.savedSearchStore = savedSearchStore
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

        if settings.openRecentSearchMenu {
            let recentMenuItem = NSMenuItem(title: "Open Recent Search", action: nil, keyEquivalent: "")
            recentMenuItem.submenu = buildRecentSearchMenu()
            appMenu.addItem(recentMenuItem)
        }

        let savedSearchMenuItem = NSMenuItem(title: "Open Saved Search", action: nil, keyEquivalent: "")
        savedSearchMenuItem.submenu = buildSavedSearchMenu()
        appMenu.addItem(savedSearchMenuItem)

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

        let fileMenuItem = NSMenuItem(title: L10n.string("menu.file"), action: nil, keyEquivalent: "")
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: L10n.string("menu.file"))
        let saveSearchItem = NSMenuItem(
            title: "Save Search…",
            action: #selector(AppDelegate.saveCurrentSearch(_:)),
            keyEquivalent: "S"
        )
        saveSearchItem.target = target
        fileMenu.addItem(saveSearchItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            NSMenuItem(
                title: L10n.string("menu.close"),
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )
        fileMenuItem.submenu = fileMenu

        let windowMenuItem = NSMenuItem(title: L10n.string("menu.window"), action: nil, keyEquivalent: "")
        mainMenu.addItem(windowMenuItem)

        let windowMenu = NSMenu(title: L10n.string("menu.window"))
        windowMenu.addItem(NSMenuItem(title: L10n.string("menu.minimize"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: L10n.string("menu.zoom"), action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = windowMenu
        windowMenuItem.submenu = windowMenu

        return mainMenu
    }

    private func buildRecentSearchMenu() -> NSMenu {
        let menu = NSMenu(title: "Open Recent Search")
        let records = searchHistoryStore.all()

        guard records.isEmpty == false else {
            let emptyItem = NSMenuItem(title: "No Recent Searches", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return menu
        }

        for record in records {
            let item = NSMenuItem(
                title: record.title,
                action: #selector(AppDelegate.openRecentSearchItem(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = record
            menu.addItem(item)
        }

        return menu
    }

    private func buildSavedSearchMenu() -> NSMenu {
        let menu = NSMenu(title: "Open Saved Search")
        let searches = savedSearchStore.all()

        guard searches.isEmpty == false else {
            let emptyItem = NSMenuItem(title: "No Saved Searches", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return menu
        }

        for search in searches {
            let title = search.compatibility == .legacySummary
                ? "\(search.name) (Summary Only)"
                : search.name
            let item = NSMenuItem(
                title: title,
                action: #selector(AppDelegate.openSavedSearchItem(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = search
            item.isEnabled = search.criteria != nil
            menu.addItem(item)
        }

        return menu
    }
}
