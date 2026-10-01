//
//  MainMenuBuilder.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit

final class MainMenuBuilder: NSObject, NSMenuDelegate {
    static let projectURL = URL(string: "https://github.com/wangwanjie/FileHound")!

    private weak var target: AnyObject?
    private let settings: AppSettings
    private let searchHistoryStore: SearchHistoryStore
    private let savedSearchStore: SavedSearchStore
    private weak var recentSearchMenu: NSMenu?
    private weak var savedSearchMenu: NSMenu?

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
        addSubmenu(buildAppMenu(), title: "FileHound", to: mainMenu)
        addSubmenu(buildFileMenu(), title: L10n.string("menu.file"), to: mainMenu)
        addSubmenu(buildEditMenu(), title: L10n.string("menu.edit"), to: mainMenu)
        addSubmenu(buildViewMenu(), title: L10n.string("menu.view"), to: mainMenu)

        let windowMenu = buildWindowMenu()
        addSubmenu(windowMenu, title: L10n.string("menu.window"), to: mainMenu)
        NSApp.windowsMenu = windowMenu

        let helpMenu = buildHelpMenu()
        addSubmenu(helpMenu, title: L10n.string("menu.help"), to: mainMenu)
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    // MARK: - NSMenuDelegate

    /// 最近 / 已存储搜索在每次展开时重新读取，保持与存储同步
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === recentSearchMenu {
            populateRecentSearchMenu(menu)
        } else if menu === savedSearchMenu {
            populateSavedSearchMenu(menu)
        }
    }

    // MARK: - Menus

    private func buildAppMenu() -> NSMenu {
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

        let checkForUpdatesItem = NSMenuItem(
            title: L10n.string("menu.check_for_updates"),
            action: #selector(AppDelegate.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = target
        checkForUpdatesItem.isEnabled = UpdateManager.shared.canCheckForUpdates
        appMenu.addItem(checkForUpdatesItem)

        appMenu.addItem(.separator())

        let servicesMenu = NSMenu(title: L10n.string("menu.services"))
        let servicesItem = NSMenuItem(title: L10n.string("menu.services"), action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(title: L10n.string("menu.hide_app"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: L10n.string("menu.hide_others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(
            title: L10n.string("menu.show_all"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.string("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        return appMenu
    }

    private func buildFileMenu() -> NSMenu {
        let fileMenu = NSMenu(title: L10n.string("menu.file"))
        let newSearchItem = NSMenuItem(
            title: L10n.string("menu.new_search"),
            action: #selector(AppDelegate.presentSearchWindow(_:)),
            keyEquivalent: "n"
        )
        newSearchItem.target = target
        fileMenu.addItem(newSearchItem)

        if settings.openRecentSearchMenu {
            let recentMenu = NSMenu(title: L10n.string("menu.open_recent_search"))
            recentMenu.delegate = self
            populateRecentSearchMenu(recentMenu)
            recentSearchMenu = recentMenu
            let recentMenuItem = NSMenuItem(title: L10n.string("menu.open_recent_search"), action: nil, keyEquivalent: "")
            recentMenuItem.submenu = recentMenu
            fileMenu.addItem(recentMenuItem)
        }

        let savedMenu = NSMenu(title: L10n.string("menu.open_saved_search"))
        savedMenu.delegate = self
        populateSavedSearchMenu(savedMenu)
        savedSearchMenu = savedMenu
        let savedSearchMenuItem = NSMenuItem(title: L10n.string("menu.open_saved_search"), action: nil, keyEquivalent: "")
        savedSearchMenuItem.submenu = savedMenu
        fileMenu.addItem(savedSearchMenuItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(
            NSMenuItem(
                title: L10n.string("results.menu.open"),
                action: #selector(SearchResultsViewController.openSelectedResults(_:)),
                keyEquivalent: "o"
            )
        )
        fileMenu.addItem(
            NSMenuItem(
                title: L10n.string("results.menu.move_to_trash"),
                action: #selector(SearchResultsViewController.moveSelectedResultsToTrash(_:)),
                keyEquivalent: "\u{8}"
            )
        )
        fileMenu.addItem(.separator())

        let saveSearchItem = NSMenuItem(
            title: L10n.string("menu.save_search"),
            action: #selector(AppDelegate.saveCurrentSearch(_:)),
            keyEquivalent: "S"
        )
        saveSearchItem.target = target
        fileMenu.addItem(saveSearchItem)
        fileMenu.addItem(
            NSMenuItem(
                title: L10n.string("menu.search_again"),
                action: #selector(SearchResultsWindowController.refreshSearchResults(_:)),
                keyEquivalent: "r"
            )
        )
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            NSMenuItem(
                title: L10n.string("menu.close"),
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )
        return fileMenu
    }

    private func buildEditMenu() -> NSMenu {
        let editMenu = NSMenu(title: L10n.string("menu.edit"))
        editMenu.addItem(withTitle: L10n.string("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L10n.string("menu.redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.string("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.string("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.string("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.string("menu.select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return editMenu
    }

    private func buildViewMenu() -> NSMenu {
        let viewMenu = NSMenu(title: L10n.string("menu.view"))
        viewMenu.addItem(
            withTitle: L10n.string("menu.view_as_icons"),
            action: #selector(SearchResultsWindowController.showResultsAsIcons(_:)),
            keyEquivalent: "1"
        )
        viewMenu.addItem(
            withTitle: L10n.string("menu.view_as_list"),
            action: #selector(SearchResultsWindowController.showResultsAsList(_:)),
            keyEquivalent: "2"
        )
        viewMenu.addItem(
            withTitle: L10n.string("menu.view_as_tree"),
            action: #selector(SearchResultsWindowController.showResultsAsTree(_:)),
            keyEquivalent: "3"
        )
        return viewMenu
    }

    private func buildWindowMenu() -> NSMenu {
        let windowMenu = NSMenu(title: L10n.string("menu.window"))
        windowMenu.addItem(NSMenuItem(title: L10n.string("menu.minimize"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: L10n.string("menu.zoom"), action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        let bringAllItem = NSMenuItem(
            title: L10n.string("menu.bring_all_to_front"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        bringAllItem.target = NSApp
        windowMenu.addItem(bringAllItem)
        return windowMenu
    }

    private func buildHelpMenu() -> NSMenu {
        let helpMenu = NSMenu(title: L10n.string("menu.help"))
        let projectItem = NSMenuItem(
            title: L10n.string("menu.project_page"),
            action: #selector(openProjectPage(_:)),
            keyEquivalent: ""
        )
        projectItem.target = self
        helpMenu.addItem(projectItem)
        return helpMenu
    }

    @objc func openProjectPage(_ sender: Any?) {
        NSWorkspace.shared.open(Self.projectURL)
    }

    @objc func clearRecentSearches(_ sender: Any?) {
        try? searchHistoryStore.removeAll()
        if let recentSearchMenu {
            populateRecentSearchMenu(recentSearchMenu)
        }
    }

    // MARK: - Dynamic submenus

    private func addSubmenu(_ submenu: NSMenu, title: String, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        mainMenu.addItem(item)
    }

    private func populateRecentSearchMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let records = searchHistoryStore.all()

        guard records.isEmpty == false else {
            let emptyItem = NSMenuItem(title: L10n.string("menu.no_recent_searches"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
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

        menu.addItem(.separator())
        let clearItem = NSMenuItem(
            title: L10n.string("menu.clear_recent_searches"),
            action: #selector(clearRecentSearches(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)
    }

    private func populateSavedSearchMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let searches = savedSearchStore.all()

        guard searches.isEmpty == false else {
            let emptyItem = NSMenuItem(title: L10n.string("menu.no_saved_searches"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }

        for search in searches {
            let title = search.compatibility == .legacySummary
                ? L10n.format("menu.saved_search_summary_only", search.name)
                : search.name
            // 仅有摘要的旧版存储无法恢复条件，不挂动作以保持禁用
            let isRestorable = search.criteria != nil
            let item = NSMenuItem(
                title: title,
                action: isRestorable ? #selector(AppDelegate.openSavedSearchItem(_:)) : nil,
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = search
            item.isEnabled = isRestorable
            menu.addItem(item)
        }
    }
}
