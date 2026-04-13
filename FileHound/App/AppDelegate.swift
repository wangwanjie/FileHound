//
//  AppDelegate.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit
import Combine
import MMKV

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var searchWindowController: SearchWindowController?
    private lazy var preferencesWindowController = PreferencesWindowController()
    private lazy var launchShortcutController: LaunchShortcutControlling = LaunchShortcutController.shared
    private lazy var updateManager: UpdateManager = .shared
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        MMKVKeyValueStore.initializeStore()
        resetSettingsForUITestingIfNeeded()
        prepareUITestFixturesIfNeeded()
        bindAppSettings()
        launchShortcutController.configure { [weak self] in
            self?.presentSearchWindow(nil)
        }
        updateManager.configureForLaunch()
        NSApp.mainMenu = MainMenuBuilder(target: self).build()

        if ProcessInfo.processInfo.arguments.contains("--open-preferences-on-launch") {
            let initialSegment: Int
            if ProcessInfo.processInfo.arguments.contains("--open-general-preferences-on-launch") {
                initialSegment = 0
            } else if ProcessInfo.processInfo.arguments.contains("--open-search-preferences-on-launch") {
                initialSegment = 1
            } else if ProcessInfo.processInfo.arguments.contains("--open-updates-preferences-on-launch") {
                initialSegment = 3
            } else {
                initialSegment = 2
            }
            preferencesWindowController.show(segment: initialSegment)
            windowController = preferencesWindowController
            NSApp.activate(ignoringOtherApps: true)
            applyCurrentTheme()
            return
        }

        presentSearchWindow(nil)
        applyCurrentTheme()

        if ProcessInfo.processInfo.arguments.contains("--open-seeded-saved-search-on-launch"),
           let savedSearch = SavedSearchStore.shared.all().first(where: { $0.name == "UI Fixture Saved Search" }),
           let criteria = savedSearch.criteria {
            searchWindowController?.apply(searchSessionSnapshot: SearchSessionSnapshot(
                criteria: criteria,
                presentationState: savedSearch.presentationState
            ))
        }

        if ProcessInfo.processInfo.arguments.contains("--show-secondary-preferences-on-launch") {
            openPreferences(nil)
        }

        if updateManager.shouldCheckOnLaunch() {
            updateManager.checkForUpdates(nil)
        }
    }

    @objc
    func openPreferences(_ sender: Any?) {
        preferencesWindowController.show(sender: sender)
        preferencesWindowController.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        applyCurrentTheme()
    }

    @objc
    func presentSearchWindow(_ sender: Any?) {
        let controller: SearchWindowController
        if let existing = searchWindowController {
            controller = existing
        } else {
            controller = SearchWindowController()
            searchWindowController = controller
        }

        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
        applyCurrentTheme()
    }

    @objc
    func checkForUpdates(_ sender: Any?) {
        updateManager.checkForUpdates(sender)
    }

    @objc
    func openRecentSearchItem(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? RecentSearchRecord else {
            return
        }

        let controller: SearchWindowController
        if let existing = searchWindowController {
            controller = existing
        } else {
            controller = SearchWindowController()
            searchWindowController = controller
        }

        controller.apply(searchSessionSnapshot: SearchSessionSnapshot(
            criteria: record.criteria,
            presentationState: record.presentationState
        ))
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    func openSavedSearchItem(_ sender: NSMenuItem) {
        guard
            let savedSearch = sender.representedObject as? SavedSearch,
            let criteria = savedSearch.criteria
        else {
            return
        }

        let controller: SearchWindowController
        if let existing = searchWindowController {
            controller = existing
        } else {
            controller = SearchWindowController()
            searchWindowController = controller
        }

        controller.apply(searchSessionSnapshot: SearchSessionSnapshot(
            criteria: criteria,
            presentationState: savedSearch.presentationState
        ))
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    func saveCurrentSearch(_ sender: Any?) {
        guard
            let controller = searchWindowController,
            let snapshot = controller.currentSearchSessionSnapshot()
        else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Save Search"
        alert.informativeText = "Enter a name for this search."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.stringValue = snapshot.criteria.querySummary
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            return
        }

        try? SavedSearchStore.shared.save(
            name: name,
            criteria: snapshot.criteria,
            presentationState: snapshot.presentationState
        )
        NSApp.mainMenu = MainMenuBuilder(target: self).build()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard flag == false else {
            return true
        }

        searchWindowController?.showWindow(sender)
        searchWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func bindAppSettings() {
        LocalizationController.shared.publisher
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadLocalizedInterface()
            }
            .store(in: &cancellables)

        ThemeController.shared.publisher
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyCurrentTheme()
            }
            .store(in: &cancellables)
    }

    private func resetSettingsForUITestingIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else {
            return
        }
        AppSettings.shared.preferredLanguage = .system
        AppSettings.shared.preferredTheme = .system
        AppSettings.shared.updateCheckPolicy = .manualOnly
        if ProcessInfo.processInfo.arguments.contains("--enable-show-results-early") {
            AppSettings.shared.showResultsEarly = true
        }
        if ProcessInfo.processInfo.arguments.contains("--disable-show-results-early") {
            AppSettings.shared.showResultsEarly = false
        }
        if ProcessInfo.processInfo.arguments.contains("--disable-tie-results-window") {
            AppSettings.shared.tieResultsWindowToFindWindow = false
        }
        if ProcessInfo.processInfo.arguments.contains("--enable-tie-results-window") {
            AppSettings.shared.tieResultsWindowToFindWindow = true
        }
        if ProcessInfo.processInfo.arguments.contains("--disable-include-spotlight-results") {
            AppSettings.shared.includeSpotlightResults = false
        }
        if ProcessInfo.processInfo.arguments.contains("--enable-include-spotlight-results") {
            AppSettings.shared.includeSpotlightResults = true
        }
        if ProcessInfo.processInfo.arguments.contains("--enable-expand-folders-results") {
            AppSettings.shared.expandFoldersWhenShowingResults = true
        }
        if ProcessInfo.processInfo.arguments.contains("--disable-expand-folders-results") {
            AppSettings.shared.expandFoldersWhenShowingResults = false
        }
    }

    private func prepareUITestFixturesIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else {
            return
        }

        if ProcessInfo.processInfo.arguments.contains("--seed-fixture-saved-search") {
            try? SavedSearchStore.shared.save(
                name: "UI Fixture Saved Search",
                criteria: SearchCriteriaSnapshot(
                    scope: SearchScopeSnapshot(
                        title: "inside Fixtures",
                        representedPath: "/tmp",
                        scopeDescription: "Fixtures",
                        sourceKind: .folder
                    ),
                    rules: [SearchRuleSelection(field: .name, operator: .contains, value: "fixture-report")]
                ),
                presentationState: ResultPresentationState(
                    mode: .table,
                    sortField: .path,
                    sortOrder: .descending,
                    filterText: "fixture",
                    showInvisibleItems: true,
                    previewSize: 88
                )
            )
        }

        if ProcessInfo.processInfo.arguments.contains("--seed-fixture-search-session") {
            AppSettings.shared.restorePreviousSearch = true
            try? SearchSessionStore.shared.save(
                SearchSessionSnapshot(
                    criteria: SearchCriteriaSnapshot(
                        scope: SearchScopeSnapshot(
                            title: "inside Fixtures",
                            representedPath: "/tmp",
                            scopeDescription: "Fixtures",
                            sourceKind: .folder
                        ),
                        rules: [SearchRuleSelection(field: .name, operator: .contains, value: "fixture-report")]
                    ),
                    presentationState: ResultPresentationState(
                        mode: .table,
                        sortField: .path,
                        sortOrder: .descending,
                        filterText: "fixture",
                        showInvisibleItems: true,
                        previewSize: 88
                    )
                )
            )
        }
    }

    private func reloadLocalizedInterface() {
        NSApp.mainMenu = MainMenuBuilder(target: self).build()
        searchWindowController?.reloadLocalizedContent()
        preferencesWindowController.reloadLocalizedContent()
        applyCurrentTheme()
    }

    private func applyCurrentTheme() {
        let theme = ThemeController.shared.currentTheme
        ThemeController.shared.apply(theme: theme, to: searchWindowController?.window)
        ThemeController.shared.apply(theme: theme, to: preferencesWindowController.window)
    }
}
