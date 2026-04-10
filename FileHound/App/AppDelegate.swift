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
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        MMKVKeyValueStore.initializeStore()
        resetSettingsForUITestingIfNeeded()
        bindAppSettings()
        NSApp.mainMenu = MainMenuBuilder(target: self).build()

        if ProcessInfo.processInfo.arguments.contains("--open-preferences-on-launch") {
            let initialSegment = ProcessInfo.processInfo.arguments.contains("--open-updates-preferences-on-launch") ? 3 : 2
            preferencesWindowController.show(segment: initialSegment)
            windowController = preferencesWindowController
            NSApp.activate(ignoringOtherApps: true)
            applyCurrentTheme()
            return
        }

        let controller = SearchWindowController()
        searchWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        windowController = controller
        applyCurrentTheme()

        if ProcessInfo.processInfo.arguments.contains("--show-secondary-preferences-on-launch") {
            openPreferences(nil)
        }

        if UpdateManager.shared.shouldCheckOnLaunch() {
            UpdateManager.shared.checkForUpdates(nil)
        }
    }

    @objc
    func openPreferences(_ sender: Any?) {
        preferencesWindowController.show(sender: sender)
        preferencesWindowController.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        applyCurrentTheme()
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
