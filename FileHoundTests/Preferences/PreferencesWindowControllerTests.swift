import AppKit
import Testing
@testable import FileHound

struct PreferencesWindowControllerTests {
    @MainActor
    @Test
    func createsCompactNonResizableWindow() {
        let controller = PreferencesWindowController()
        let window = try! #require(controller.window)

        #expect(window.styleMask.contains(.resizable) == false)
        #expect(window.contentLayoutRect.width < 700)
        #expect(window.contentLayoutRect.height < 500)
    }

    @MainActor
    @Test
    func activeSectionUsesRoundedCardBackground() {
        let controller = PreferencesWindowController()
        controller.show()

        let rootController = try! #require(controller.window?.contentViewController as? PreferencesRootViewController)
        #expect(rootController.debugActiveSectionHasCardBackground == true)
    }

    @MainActor
    @Test
    func preferencesRootBackgroundRefreshesAcrossAppearances() {
        let controller = PreferencesRootViewController(initialSegment: 0)
        _ = controller.view

        let light = controller.debugRootBackgroundHex(for: .aqua)
        let dark = controller.debugRootBackgroundHex(for: .darkAqua)

        #expect(light != dark)
    }
}

struct AppearancePreferencesViewControllerTests {
    @MainActor
    @Test
    func appearanceSelectionsUpdateThemeAndLanguageControllers() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        let themeController = ThemeController(settings: settings)
        let localizationController = LocalizationController(settings: settings)
        let controller = AppearancePreferencesViewController(
            settings: settings,
            themeController: themeController,
            localizationController: localizationController
        )
        _ = controller.view

        controller.debugSelectTheme(.dark)
        controller.debugSelectLanguage(.en)

        #expect(settings.preferredTheme == .dark)
        #expect(themeController.currentTheme == .dark)
        #expect(settings.preferredLanguage == .en)
        #expect(localizationController.currentLanguage == .en)
    }

    @MainActor
    @Test
    func appearanceResetReturnsSettingsToDefaults() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.preferredTheme = .dark
        settings.preferredLanguage = .en
        settings.resultsFontSize = 18
        settings.dimColorHex = "#6E7E91"
        let controller = AppearancePreferencesViewController(
            settings: settings,
            themeController: ThemeController(settings: settings),
            localizationController: LocalizationController(settings: settings)
        )
        _ = controller.view

        controller.debugTriggerResetDefaults()

        #expect(settings.preferredTheme == .system)
        #expect(settings.preferredLanguage == .system)
        #expect(settings.resultsFontSize == 13)
        #expect(settings.dimColorHex == "#A0A7B3")
        #expect(controller.debugSelectedTheme == .system)
        #expect(controller.debugSelectedLanguage == .system)
        #expect(controller.debugFontSizeValue == 13)
        #expect(controller.debugDimColorHex == "#A0A7B3")
    }

    @MainActor
    @Test
    func dimColorSelectionUpdatesSettingAndPreview() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        let controller = AppearancePreferencesViewController(
            settings: settings,
            themeController: ThemeController(settings: settings),
            localizationController: LocalizationController(settings: settings)
        )
        _ = controller.view

        controller.debugApplyDimColor(NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.76, alpha: 1))

        #expect(settings.dimColorHex == "#2E6BC2")
        #expect(controller.debugDimColorHex == "#2E6BC2")
        #expect(controller.debugDimColorPreviewHex == "#2E6BC2")
    }
}

struct GeneralPreferencesViewControllerTests {
    @MainActor
    @Test
    func shortcutRecorderCapturesNormalizedShortcutAndUsesTallerControl() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        let shortcutController = LaunchShortcutController(
            settings: settings,
            hotKeyRegistrar: TestHotKeyRegistrar(),
            shortcutMonitor: TestShortcutMonitor(),
            frontmostApplicationProvider: { nil }
        )
        let controller = GeneralPreferencesViewController(
            settings: settings,
            launchShortcutController: shortcutController
        )
        _ = controller.view

        controller.debugRecordShortcut(.init(keyCode: 49, modifierFlags: [.command, .shift]))

        #expect(settings.launchShortcut == "cmd-shift-space")
        #expect(controller.debugDisplayedLaunchShortcut == "⌘⇧Space")
        #expect(controller.debugHotKeyControlHeight >= 30)
    }
}

struct LaunchShortcutControllerTests {
    @MainActor
    @Test
    func globalShortcutRegistersCarbonHotKeyAndInvokesAction() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.launchShortcut = "cmd-shift-space"
        settings.activationMode = .global
        let registrar = TestHotKeyRegistrar()
        let monitor = TestShortcutMonitor()
        var triggerCount = 0
        let controller = LaunchShortcutController(
            settings: settings,
            hotKeyRegistrar: registrar,
            shortcutMonitor: monitor,
            frontmostApplicationProvider: { "com.apple.finder" }
        )

        controller.configure {
            triggerCount += 1
        }
        registrar.trigger()

        #expect(registrar.registeredShortcut == KeyboardShortcut(keyCode: 49, modifierFlags: [.command, .shift]))
        #expect(monitor.isMonitoring == false)
        #expect(triggerCount == 1)
    }

    @MainActor
    @Test
    func finderOnlyShortcutUsesMonitorAndOnlyTriggersWhenFinderIsFrontmost() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.launchShortcut = "cmd-shift-space"
        settings.activationMode = .finderOnly
        let registrar = TestHotKeyRegistrar()
        let monitor = TestShortcutMonitor()
        var frontmostBundleIdentifier = "com.apple.TextEdit"
        var triggerCount = 0
        let controller = LaunchShortcutController(
            settings: settings,
            hotKeyRegistrar: registrar,
            shortcutMonitor: monitor,
            frontmostApplicationProvider: { frontmostBundleIdentifier }
        )

        controller.configure {
            triggerCount += 1
        }
        monitor.send(.init(keyCode: 49, modifierFlags: [.command, .shift]))
        frontmostBundleIdentifier = "com.apple.finder"
        monitor.send(.init(keyCode: 49, modifierFlags: [.command, .shift]))

        #expect(registrar.registeredShortcut == nil)
        #expect(monitor.isMonitoring == true)
        #expect(triggerCount == 1)
    }
}

struct UpdatePreferencesViewControllerTests {
    @MainActor
    @Test
    func updateResetReturnsSettingsToDefaults() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.updateCheckPolicy = .dailyAutomatic
        settings.autoDownloadUpdates = true
        let controller = UpdatePreferencesViewController(settings: settings)
        _ = controller.view

        controller.debugTriggerResetDefaults()

        #expect(settings.updateCheckPolicy == .onLaunch)
        #expect(settings.autoDownloadUpdates == false)
        #expect(controller.debugSelectedPolicyIndex == 0)
        #expect(controller.debugAutoDownloadEnabled == false)
    }
}

struct SpecialFoldersEditorViewControllerTests {
    @MainActor
    @Test
    func specialFoldersEditorPersistsAddedUpdatedAndRemovedRules() throws {
        let storage = InMemoryKeyValueStore()
        let store = SpecialFoldersStore(storage: storage)
        let controller = SpecialFoldersEditorViewController(store: store)
        _ = controller.view

        controller.debugAddRule(path: "/Users/test/Library", disposition: .exclude)
        controller.debugAddRule(path: "/Users/test/Downloads", disposition: .slowSearch)
        controller.debugSetDisposition(.include, at: 0)
        controller.debugRemoveRule(at: 1)

        let rules = store.load().rules
        #expect(rules.count == 1)
        #expect(rules.first?.path == "/Users/test/Library")
        #expect(rules.first?.disposition == .include)
        #expect(controller.debugRules == rules)
    }

    @MainActor
    @Test
    func specialFoldersEditorIgnoresDuplicatePathsAfterStandardization() {
        let storage = InMemoryKeyValueStore()
        let store = SpecialFoldersStore(storage: storage)
        let controller = SpecialFoldersEditorViewController(store: store)
        _ = controller.view

        controller.debugAddRule(path: "/Users/test/Library", disposition: .exclude)
        controller.debugAddRule(path: "/Users/test/Library/", disposition: .include)

        let rules = store.load().rules
        #expect(rules.count == 1)
        #expect(rules.first?.path == "/Users/test/Library")
        #expect(rules.first?.disposition == .exclude)
    }

    @MainActor
    @Test
    func specialFoldersEditorUsesNativeListControls() throws {
        let storage = InMemoryKeyValueStore()
        let store = SpecialFoldersStore(storage: storage)
        let controller = SpecialFoldersEditorViewController(store: store)
        let view = controller.view

        let tableView = try #require(findView(of: NSTableView.self, in: view))
        let addButton = try #require(findButton(identifier: "SpecialFoldersAddButton", in: view))
        let removeButton = try #require(findButton(identifier: "SpecialFoldersRemoveButton", in: view))

        #expect(tableView.usesAlternatingRowBackgroundColors == true)
        #expect(addButton.isEnabled == true)
        #expect(removeButton.isEnabled == false)
    }

    @MainActor
    @Test
    func specialFoldersEditorDeletesSelectedRulesFromRemoveButton() throws {
        let storage = InMemoryKeyValueStore()
        let store = seededSpecialFoldersStore(storage: storage)
        let controller = SpecialFoldersEditorViewController(store: store)
        let view = controller.view

        let tableView = try #require(findView(of: NSTableView.self, in: view))
        let removeButton = try #require(findButton(identifier: "SpecialFoldersRemoveButton", in: view))

        tableView.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
        removeButton.performClick(nil)

        let rules = store.load().rules
        #expect(rules.map(\.path) == ["/Users/test/Downloads"])
        #expect(controller.debugRules == rules)
    }

    @MainActor
    @Test
    func specialFoldersEditorDeletesSelectedRulesFromContextMenuAction() throws {
        let storage = InMemoryKeyValueStore()
        let store = seededSpecialFoldersStore(storage: storage)
        let controller = SpecialFoldersEditorViewController(store: store)
        let view = controller.view

        let tableView = try #require(findView(of: NSTableView.self, in: view))
        tableView.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)

        let selector = NSSelectorFromString("debugDeleteSelectedRulesFromContextMenu")
        #expect(controller.responds(to: selector) == true)
        _ = controller.perform(selector)

        let rules = store.load().rules
        #expect(rules.map(\.path) == ["/Users/test/Desktop"])
        #expect(controller.debugRules == rules)
    }

    @MainActor
    @Test
    func specialFoldersEditorPersistsDraggedRuleOrder() throws {
        let storage = InMemoryKeyValueStore()
        let store = seededSpecialFoldersStore(storage: storage)
        let controller = SpecialFoldersEditorViewController(store: store)
        _ = controller.view

        let selector = NSSelectorFromString("debugMoveRuleFromIndex:toIndex:")
        #expect(controller.responds(to: selector) == true)
        _ = controller.perform(selector, with: NSNumber(value: 0), with: NSNumber(value: 2))

        let rules = store.load().rules
        #expect(rules.map(\.path) == [
            "/Users/test/Downloads",
            "/Users/test/Desktop",
            "/Users/test/Library"
        ])
        #expect(controller.debugRules == rules)
    }

    @MainActor
    @Test
    func specialFoldersWindowUsesOuterPaddingAndThreePointFiveVisibleRowsByDefault() throws {
        let controller = SpecialFoldersWindowController(store: SpecialFoldersStore(storage: InMemoryKeyValueStore()))
        controller.showWindow(nil)

        let window = try #require(controller.window)
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()

        let sectionView = try #require(findView(of: PreferencesSectionView.self, in: contentView))
        let scrollView = try #require(findView(of: NSScrollView.self, in: contentView))

        #expect(sectionView.frame.minX >= 20)
        #expect(sectionView.frame.minY >= 20)
        #expect(contentView.bounds.maxX - sectionView.frame.maxX >= 20)
        #expect(abs(scrollView.frame.height - 119) < 2)
    }

    @MainActor
    @Test
    func specialFoldersEditorUsesBorderlessListAndCenteredControlGlyphs() {
        let controller = SpecialFoldersEditorViewController(store: SpecialFoldersStore(storage: InMemoryKeyValueStore()))
        _ = controller.view

        #expect(controller.debugListBorderType == .noBorder)
        #expect(controller.debugAddButtonImageAlignmentOffset < 1.5)
        #expect(controller.debugRemoveButtonImageAlignmentOffset < 1.5)
    }

    @MainActor
    @Test
    func specialFoldersEditorUsesDistinctAlternatingRowBackgrounds() {
        let controller = SpecialFoldersEditorViewController(store: seededSpecialFoldersStore(storage: InMemoryKeyValueStore()))
        _ = controller.view

        let listBackground = controller.debugListBackgroundHex(for: .aqua)
        let firstRowBackground = controller.debugRowBackgroundHex(for: 0, appearanceName: .aqua)
        let secondRowBackground = controller.debugRowBackgroundHex(for: 1, appearanceName: .aqua)

        #expect(firstRowBackground != secondRowBackground)
        #expect(secondRowBackground != listBackground)
    }

    @MainActor
    @Test
    func specialFoldersEditorUsesMatchingSquareListControlButtons() {
        let controller = SpecialFoldersEditorViewController(store: SpecialFoldersStore(storage: InMemoryKeyValueStore()))
        _ = controller.view

        let addSize = controller.debugAddButtonSize
        let removeSize = controller.debugRemoveButtonSize

        #expect(addSize == removeSize)
        #expect(abs(addSize.width - addSize.height) < 0.5)
    }

    @MainActor
    @Test
    func specialFoldersRootBackgroundRefreshesAcrossAppearances() {
        let controller = SpecialFoldersEditorViewController(store: SpecialFoldersStore(storage: InMemoryKeyValueStore()))
        _ = controller.view

        let light = controller.debugRootBackgroundHex(for: .aqua)
        let dark = controller.debugRootBackgroundHex(for: .darkAqua)

        #expect(light != dark)
    }

    @MainActor
    @Test
    func specialFoldersWindowTracksThemeControllerChanges() throws {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        let themeController = ThemeController(settings: settings)
        let controller = SpecialFoldersWindowController(
            store: SpecialFoldersStore(storage: storage),
            themeController: themeController
        )
        controller.showWindow(nil)

        let window = try #require(controller.window)
        themeController.select(theme: .dark)

        #expect(window.appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }
}

struct PreferencesAppearanceRefreshTests {
    @MainActor
    @Test
    func preferencesCardBackgroundRefreshesAcrossAppearances() {
        let sectionView = PreferencesSectionView(title: "General", subtitle: "Settings")

        let light = sectionView.debugCardBackgroundHex(for: .aqua)
        let dark = sectionView.debugCardBackgroundHex(for: .darkAqua)

        #expect(light != dark)
    }
}

private final class TestHotKeyRegistrar: HotKeyRegistering {
    private(set) var registeredShortcut: KeyboardShortcut?
    private(set) var registerCallCount = 0
    private var handler: (() -> Void)?

    @discardableResult
    func register(shortcut: KeyboardShortcut, handler: @escaping () -> Void) -> Bool {
        registerCallCount += 1
        registeredShortcut = shortcut
        self.handler = handler
        return true
    }

    func unregister() {
        registeredShortcut = nil
        handler = nil
    }

    func trigger() {
        handler?()
    }
}

private final class TestShortcutMonitor: ShortcutMonitoring {
    private(set) var isMonitoring = false
    private(set) var deliveredShortcuts: [KeyboardShortcut] = []
    private var handler: ((KeyboardShortcut) -> Void)?

    func startMonitoring(handler: @escaping (KeyboardShortcut) -> Void) {
        isMonitoring = true
        self.handler = handler
    }

    func stopMonitoring() {
        isMonitoring = false
        handler = nil
    }

    func send(_ shortcut: KeyboardShortcut) {
        deliveredShortcuts.append(shortcut)
        handler?(shortcut)
    }
}

private func seededSpecialFoldersStore(storage: InMemoryKeyValueStore) -> SpecialFoldersStore {
    let store = SpecialFoldersStore(storage: storage)
    try? store.save(
        SpecialFoldersConfiguration(
            rules: [
                SpecialFolderRule(path: "/Users/test/Library", disposition: .exclude),
                SpecialFolderRule(path: "/Users/test/Downloads", disposition: .slowSearch),
                SpecialFolderRule(path: "/Users/test/Desktop", disposition: .include)
            ]
        )
    )
    return store
}

private func findButton(identifier: String, in view: NSView) -> NSButton? {
    findView(in: view) { candidate in
        (candidate as? NSButton)?.accessibilityIdentifier() == identifier
    } as? NSButton
}

private func findView<T: NSView>(of type: T.Type, in view: NSView) -> T? {
    findView(in: view) { $0 is T } as? T
}

private func findView(in view: NSView, where predicate: (NSView) -> Bool) -> NSView? {
    if predicate(view) {
        return view
    }

    for subview in view.subviews {
        if let match = findView(in: subview, where: predicate) {
            return match
        }
    }

    return nil
}
