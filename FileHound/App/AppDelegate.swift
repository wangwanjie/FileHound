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
    private var windowController: SearchWindowController?
    private lazy var preferencesWindowController = PreferencesWindowController()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        MMKVKeyValueStore.initializeStore()
        resetSettingsForUITestingIfNeeded()
        bindAppSettings()
        NSApp.mainMenu = MainMenuBuilder(target: self).build()

        let controller = SearchWindowController()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        windowController = controller
        applyCurrentTheme()
    }

    @objc
    func openPreferences(_ sender: Any?) {
        preferencesWindowController.showWindow(sender)
        preferencesWindowController.window?.makeKeyAndOrderFront(sender)
        applyCurrentTheme()
    }

    private func bindAppSettings() {
        LocalizationController.shared.publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadLocalizedInterface()
            }
            .store(in: &cancellables)

        ThemeController.shared.publisher
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
    }

    private func reloadLocalizedInterface() {
        NSApp.mainMenu = MainMenuBuilder(target: self).build()
        if let window = windowController?.window {
            window.contentViewController = SearchFormViewController()
        }

        let preferencesVisible = preferencesWindowController.window?.isVisible == true
        preferencesWindowController = PreferencesWindowController()
        if preferencesVisible {
            openPreferences(nil)
        }

        applyCurrentTheme()
    }

    private func applyCurrentTheme() {
        let theme = ThemeController.shared.currentTheme
        ThemeController.shared.apply(theme: theme, to: windowController?.window)
        ThemeController.shared.apply(theme: theme, to: preferencesWindowController.window)
    }
}
