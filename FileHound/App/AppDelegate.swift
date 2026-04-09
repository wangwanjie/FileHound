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
    private lazy var preferencesWindowController = PreferencesWindowController()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        MMKVKeyValueStore.initializeStore()
        resetSettingsForUITestingIfNeeded()
        bindAppSettings()
        NSApp.mainMenu = MainMenuBuilder(target: self).build()

        if ProcessInfo.processInfo.arguments.contains("--open-preferences-on-launch") {
            let initialSegment = ProcessInfo.processInfo.arguments.contains("--open-updates-preferences-on-launch") ? 3 : 2
            let rootViewController = PreferencesRootViewController(initialSegment: initialSegment)
            let window = NSWindow(contentViewController: rootViewController)
            window.title = L10n.string("preferences.window.title")
            window.setContentSize(NSSize(width: 760, height: 560))
            window.styleMask = [.titled, .closable, .miniaturizable]
            let controller = NSWindowController(window: window)
            controller.showWindow(nil)
            windowController = controller
            NSApp.activate(ignoringOtherApps: true)
            applyCurrentTheme()
            return
        }

        let controller = SearchWindowController()
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
        preferencesWindowController.showWindow(sender)
        preferencesWindowController.window?.makeKeyAndOrderFront(sender)
        preferencesWindowController.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        applyCurrentTheme()
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
