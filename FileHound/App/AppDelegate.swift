//
//  AppDelegate.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit
import Combine
import MMKV

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var windowController: NSWindowController?
    private lazy var searchWindowManager: SearchWindowManager = {
        let manager = SearchWindowManager()
        manager.onControllerCreated = { [weak self] _ in
            self?.applyCurrentTheme()
        }
        return manager
    }()
    private lazy var preferencesWindowController = PreferencesWindowController()
    private lazy var launchShortcutController: LaunchShortcutControlling = LaunchShortcutController.shared
    /// 延迟创建：UpdateManager.shared 会创建真实的 Sparkle 控制器，测试中构造 AppDelegate 时不应触发
    private let updateManagerProvider: () -> UpdateManager
    private lazy var updateManager: UpdateManager = updateManagerProvider()
    private var cancellables: Set<AnyCancellable> = []
    /// 菜单构建器同时是最近 / 已存储搜索子菜单的 delegate，需要强引用
    private var mainMenuBuilder: MainMenuBuilder?
    /// 本实例作为单元测试 test host 完成了启动（只在 applicationDidFinishLaunching 中设置，测试自行构造的实例不受影响）
    private var isHostingUnitTests = false

    init(updateManagerProvider: @escaping () -> UpdateManager = { .shared }) {
        self.updateManagerProvider = updateManagerProvider
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MMKVKeyValueStore.initializeStore()

        // 作为单元测试的 test host 运行时，只保留 MMKV 等测试需要的基础设施（且已切到独立目录），
        // 跳过全局热键注册、更新检查、窗口恢复 / 打开等会影响用户环境的启动副作用
        guard AppRuntimeEnvironment.isRunningUnitTests == false else {
            isHostingUnitTests = true
            return
        }

        resetSettingsForUITestingIfNeeded()
        prepareUITestFixturesIfNeeded()
        bindAppSettings()
        launchShortcutController.configure { [weak self] in
            self?.presentSearchWindow(nil)
        }
        rebuildMainMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMainMenuNeedsRebuild(_:)),
            name: .mainMenuNeedsRebuild,
            object: nil
        )

        // 应用更新策略；「启动时检查」走后台静默检查（只有发现新版本才提示），Debug 构建不自动检查
        updateManager.handleLaunch()

        if ProcessInfo.processInfo.arguments.contains("--open-preferences-on-launch") {
            let initialSegment: Int
            if ProcessInfo.processInfo.arguments.contains("--open-general-preferences-on-launch") {
                initialSegment = 0
            } else if ProcessInfo.processInfo.arguments.contains("--open-search-preferences-on-launch") {
                initialSegment = 1
            } else if ProcessInfo.processInfo.arguments.contains("--open-updates-preferences-on-launch") {
                initialSegment = 3
            } else if ProcessInfo.processInfo.arguments.contains("--open-permissions-preferences-on-launch") {
                initialSegment = 4
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
            searchWindowManager.activeController?.apply(searchSessionSnapshot: SearchSessionSnapshot(
                criteria: criteria,
                presentationState: savedSearch.presentationState
            ))
        }

        if ProcessInfo.processInfo.arguments.contains("--show-secondary-preferences-on-launch") {
            openPreferences(nil)
        }
    }

    @objc
    func openPreferences(_ sender: Any?) {
        preferencesWindowController.show(sender: sender)
        preferencesWindowController.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        applyCurrentTheme()
    }

    /// 显示当前查找窗口（启动、全局快捷键），不存在时才新建
    @objc
    func presentSearchWindow(_ sender: Any?) {
        windowController = searchWindowManager.presentActiveWindow()
        NSApp.activate(ignoringOtherApps: true)
        applyCurrentTheme()
    }

    /// 菜单「新建搜索」（⌘N）：另开一个空白查找窗口，保留其他窗口的条件与结果
    @objc
    func newSearchWindow(_ sender: Any?) {
        windowController = searchWindowManager.openNewWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    func checkForUpdates(_ sender: Any?) {
        updateManager.checkForUpdates(sender)
    }

    // MARK: - NSMenuItemValidation

    /// 主菜单开启了 autoenablesItems，直接设置 isEnabled 无效，需要在这里校验
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return updateManager.canCheckForUpdates
        }
        return true
    }

    @objc
    func openRecentSearchItem(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? RecentSearchRecord else {
            return
        }

        let controller = searchWindowManager.controllerForApplyingSnapshot()
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

        let controller = searchWindowManager.controllerForApplyingSnapshot()
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
            let controller = searchWindowManager.activeController,
            let snapshot = controller.currentSearchSessionSnapshot()
        else {
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.string("save_search.title")
        alert.informativeText = L10n.string("save_search.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.string("common.save"))
        alert.addButton(withTitle: L10n.string("common.cancel"))

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
        rebuildMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 单元测试 test host 启动时不打开任何窗口，测试关闭自己创建的窗口后不能让宿主进程退出
        guard isHostingUnitTests == false else {
            return false
        }
        return AppSettings.shared.quitWhenAllWindowsAreClosed
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard flag == false else {
            return true
        }

        presentSearchWindow(sender)
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

    @objc
    private func handleMainMenuNeedsRebuild(_ notification: Notification) {
        rebuildMainMenu()
    }

    private func rebuildMainMenu() {
        let builder = MainMenuBuilder(target: self)
        mainMenuBuilder = builder
        NSApp.mainMenu = builder.build()
    }

    private func reloadLocalizedInterface() {
        rebuildMainMenu()
        searchWindowManager.reloadLocalizedContent()
        preferencesWindowController.reloadLocalizedContent()
        applyCurrentTheme()
    }

    /// 主题设置在 NSApp 上：所有窗口（查找、结果、偏好设置）以及 NSAlert、NSOpenPanel 等系统面板都会继承
    private func applyCurrentTheme() {
        ThemeController.shared.applyToApplication(theme: ThemeController.shared.currentTheme)
    }
}
