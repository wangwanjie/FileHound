import AppKit
import Testing
@testable import FileHound

struct PreferencesWindowControllerTests {
    @MainActor
    @Test
    func createsCompactNonResizableWindow() {
        let controller = PreferencesWindowController(dependencies: makeTestPreferencesDependencies())
        let window = try! #require(controller.window)
        defer {
            window.close()
        }

        #expect(window.styleMask.contains(.resizable) == false)
        #expect(window.contentLayoutRect.width < 700)
        #expect(window.contentLayoutRect.height < 500)
    }

    @MainActor
    @Test
    func activeSectionUsesRoundedCardBackground() {
        let controller = PreferencesWindowController(dependencies: makeTestPreferencesDependencies())
        controller.show()
        defer {
            controller.window?.close()
        }

        let rootController = try! #require(controller.window?.contentViewController as? PreferencesRootViewController)
        #expect(rootController.debugActiveSectionHasCardBackground == true)
    }

    @MainActor
    @Test
    func preferencesRootBackgroundRefreshesAcrossAppearances() {
        let controller = PreferencesRootViewController(
            initialSegment: 0,
            contentControllers: makeTestPreferencesDependencies().makeContentControllers()
        )
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
        // 使用范围内的非默认值，确保重置确实改变了字号
        settings.resultsFontSize = 15
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
    func outOfRangeStoredFontSizeIsClampedForDisplay() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        // 旧版本允许更大的字号
        settings.resultsFontSize = 18
        let controller = AppearancePreferencesViewController(
            settings: settings,
            themeController: ThemeController(settings: settings),
            localizationController: LocalizationController(settings: settings)
        )
        _ = controller.view

        #expect(controller.debugFontSizeValue == 16)
        #expect(controller.debugFontSizeFieldText == "16")
    }

    @MainActor
    @Test
    func fontSizeFieldEntryIsValidatedClampedAndSaved() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        let controller = AppearancePreferencesViewController(
            settings: settings,
            themeController: ThemeController(settings: settings),
            localizationController: LocalizationController(settings: settings)
        )
        _ = controller.view

        controller.debugEnterFontSize(" 15 ")
        #expect(settings.resultsFontSize == 15)
        #expect(controller.debugFontSizeValue == 15)
        #expect(controller.debugFontSizeFieldText == "15")

        controller.debugEnterFontSize("40")
        #expect(settings.resultsFontSize == 16)
        #expect(controller.debugFontSizeValue == 16)
        #expect(controller.debugFontSizeFieldText == "16")

        controller.debugEnterFontSize("3")
        #expect(settings.resultsFontSize == 10)
        #expect(controller.debugFontSizeFieldText == "10")

        controller.debugEnterFontSize("abc")
        #expect(settings.resultsFontSize == 10)
        #expect(controller.debugFontSizeFieldText == "10")
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
            frontmostApplicationObserver: TestFrontmostApplicationObserver(),
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

    @MainActor
    @Test
    func recordingShortcutSuspendsGlobalHotKeyUntilRecordingEnds() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        settings.launchShortcut = "cmd-shift-space"
        settings.activationMode = .global
        let registrar = TestHotKeyRegistrar()
        let shortcutController = LaunchShortcutController(
            settings: settings,
            hotKeyRegistrar: registrar,
            frontmostApplicationObserver: TestFrontmostApplicationObserver(),
            frontmostApplicationProvider: { nil }
        )
        shortcutController.configure {}
        let controller = GeneralPreferencesViewController(settings: settings, launchShortcutController: shortcutController)
        _ = controller.view
        #expect(registrar.registeredShortcut != nil)

        controller.debugHotKeyField.debugSetRecording(true)
        #expect(registrar.registeredShortcut == nil)

        // 录制期间保存新快捷键也不能重新注册
        controller.debugRecordShortcut(.init(keyCode: 40, modifierFlags: [.command, .option]))
        #expect(registrar.registeredShortcut == nil)

        controller.debugHotKeyField.debugSetRecording(false)
        #expect(registrar.registeredShortcut == KeyboardShortcut(keyCode: 40, modifierFlags: [.command, .option]))
    }

    @MainActor
    @Test
    func recorderInterceptsCommandKeyEquivalentsWhileFirstResponder() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer {
            window.close()
        }
        let field = ShortcutRecorderField(frame: NSRect(x: 0, y: 0, width: 180, height: 32))
        window.contentView?.addSubview(field)
        let commandQ = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "q",
            charactersIgnoringModifiers: "q",
            isARepeat: false,
            keyCode: 12
        ))

        // 不是第一响应者时不拦截，交给菜单等正常处理
        #expect(field.performKeyEquivalent(with: commandQ) == false)
        #expect(field.shortcut == nil)

        #expect(window.makeFirstResponder(field))
        #expect(field.performKeyEquivalent(with: commandQ) == true)
        #expect(field.shortcut == KeyboardShortcut(keyCode: 12, modifierFlags: [.command]))
    }
}

struct KeyboardShortcutTests {
    @Test
    func serializationRoundTrips() throws {
        let shortcut = KeyboardShortcut(keyCode: 49, modifierFlags: [.command, .control, .option, .shift])
        let restored = try #require(KeyboardShortcut(serialized: shortcut.serialized))

        #expect(shortcut.serialized == "cmd-ctrl-opt-shift-space")
        #expect(restored == shortcut)
        #expect(KeyboardShortcut(serialized: " Command+Alt+K ") == KeyboardShortcut(keyCode: 40, modifierFlags: [.command, .option]))
    }

    @Test
    func rejectsInvalidTokens() {
        #expect(KeyboardShortcut(serialized: "") == nil)
        #expect(KeyboardShortcut(serialized: "cmd-unknownkey") == nil)
        #expect(KeyboardShortcut(serialized: "hyper-space") == nil)
        #expect(KeyboardShortcut(serialized: "space") == nil)
    }

    @Test
    func rejectsShiftOnlyCombinationLikeCapture() {
        // 与 capture 的规则一致：必须带 ⌘ / ⌃ / ⌥ 之一
        #expect(KeyboardShortcut(serialized: "shift-space") == nil)
        #expect(KeyboardShortcut(serialized: "ctrl-shift-space") != nil)
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
        let observer = TestFrontmostApplicationObserver()
        var triggerCount = 0
        let controller = LaunchShortcutController(
            settings: settings,
            hotKeyRegistrar: registrar,
            frontmostApplicationObserver: observer,
            frontmostApplicationProvider: { "com.apple.finder" }
        )

        controller.configure {
            triggerCount += 1
        }
        registrar.trigger()

        #expect(registrar.registeredShortcut == KeyboardShortcut(keyCode: 49, modifierFlags: [.command, .shift]))
        #expect(observer.isObserving == false)
        #expect(triggerCount == 1)
    }

    @MainActor
    @Test
    func finderOnlyShortcutRegistersHotKeyOnlyWhileFinderIsFrontmost() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.launchShortcut = "cmd-shift-space"
        settings.activationMode = .finderOnly
        let registrar = TestHotKeyRegistrar()
        let observer = TestFrontmostApplicationObserver()
        var triggerCount = 0
        let controller = LaunchShortcutController(
            settings: settings,
            hotKeyRegistrar: registrar,
            frontmostApplicationObserver: observer,
            frontmostApplicationProvider: { "com.apple.TextEdit" }
        )

        controller.configure {
            triggerCount += 1
        }
        #expect(observer.isObserving == true)
        #expect(registrar.registeredShortcut == nil)

        observer.activate("com.apple.finder")
        #expect(registrar.registeredShortcut == KeyboardShortcut(keyCode: 49, modifierFlags: [.command, .shift]))
        registrar.trigger()
        #expect(triggerCount == 1)

        observer.activate("com.apple.Safari")
        #expect(registrar.registeredShortcut == nil)

        settings.activationMode = .global
        controller.reload()
        #expect(observer.isObserving == false)
        #expect(registrar.registeredShortcut != nil)
    }

    @MainActor
    @Test
    func clearingShortcutUnregistersHotKey() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        settings.launchShortcut = "cmd-shift-space"
        settings.activationMode = .global
        let registrar = TestHotKeyRegistrar()
        let controller = LaunchShortcutController(
            settings: settings,
            hotKeyRegistrar: registrar,
            frontmostApplicationObserver: TestFrontmostApplicationObserver(),
            frontmostApplicationProvider: { nil }
        )
        controller.configure {}
        #expect(registrar.registeredShortcut != nil)

        settings.launchShortcut = ""
        controller.reload()

        #expect(registrar.registeredShortcut == nil)
    }

    @MainActor
    @Test
    func suspendUnregistersAndResumeRestoresHotKey() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        settings.launchShortcut = "cmd-shift-space"
        settings.activationMode = .finderOnly
        let registrar = TestHotKeyRegistrar()
        let observer = TestFrontmostApplicationObserver()
        let controller = LaunchShortcutController(
            settings: settings,
            hotKeyRegistrar: registrar,
            frontmostApplicationObserver: observer,
            frontmostApplicationProvider: { "com.apple.finder" }
        )
        controller.configure {}
        #expect(registrar.registeredShortcut != nil)

        controller.suspend()
        #expect(registrar.registeredShortcut == nil)
        #expect(observer.isObserving == false)
        controller.reload()
        #expect(registrar.registeredShortcut == nil)

        controller.resume()
        #expect(registrar.registeredShortcut == KeyboardShortcut(keyCode: 49, modifierFlags: [.command, .shift]))
        #expect(observer.isObserving == true)
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
        let driver = StubSparkleDriver(canCheckForUpdates: true)
        let controller = UpdatePreferencesViewController(
            settings: settings,
            updateManager: makeUpdateManager(settings: settings, driver: driver)
        )
        _ = controller.view

        controller.debugTriggerResetDefaults()

        #expect(settings.updateCheckPolicy == .onLaunch)
        #expect(settings.autoDownloadUpdates == false)
        #expect(controller.debugSelectedPolicyIndex == 0)
        #expect(controller.debugAutoDownloadEnabled == false)
        #expect(driver.appliedPolicies.last == .onLaunch)
        #expect(driver.appliedAutoDownloadFlags.last == false)
    }

    @MainActor
    @Test
    func changingPolicyAndAutoDownloadAppliesToSparkleImmediately() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        settings.updateCheckPolicy = .manualOnly
        let driver = StubSparkleDriver(canCheckForUpdates: true)
        let controller = UpdatePreferencesViewController(
            settings: settings,
            updateManager: makeUpdateManager(settings: settings, driver: driver)
        )
        _ = controller.view

        controller.debugSelectPolicy(at: 2)
        #expect(settings.updateCheckPolicy == .dailyAutomatic)
        #expect(driver.appliedPolicies == [.dailyAutomatic])
        // 切到「每天自动检查」需立即启动 updater 排期，不必重启
        #expect(driver.startCalls == 1)

        controller.debugSetAutoDownload(true)
        #expect(settings.autoDownloadUpdates == true)
        #expect(driver.appliedAutoDownloadFlags.last == true)
        #expect(driver.checkCalls == 0)
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

struct ThemeControllerTests {
    @MainActor
    @Test
    func applyMapsThemesToAppearances() {
        let themeController = ThemeController(settings: AppSettings(storage: InMemoryKeyValueStore()))
        let view = NSView()

        themeController.apply(theme: .dark, to: view)
        #expect(view.appearance?.name == .darkAqua)
        themeController.apply(theme: .light, to: view)
        #expect(view.appearance?.name == .aqua)
        themeController.apply(theme: .system, to: view)
        #expect(view.appearance == nil)
    }

    @MainActor
    @Test
    func applyToApplicationSetsAppWideAppearanceSoAllWindowsInherit() {
        let themeController = ThemeController(settings: AppSettings(storage: InMemoryKeyValueStore()))
        let previous = NSApp.appearance
        defer {
            NSApp.appearance = previous
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer {
            window.close()
        }

        themeController.applyToApplication(theme: .dark)
        #expect(NSApp.appearance?.name == .darkAqua)
        // 未单独设置外观的窗口（结果窗口、NSAlert 等）继承 App 外观
        #expect(window.appearance == nil)
        #expect(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)

        themeController.applyToApplication(theme: .system)
        #expect(NSApp.appearance == nil)
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

/// 偏好设置测试依赖：内存存储、假 Sparkle 驱动、假热键注册器，避免触碰真实 MMKV / Sparkle / 全局热键
@MainActor
func makeTestPreferencesDependencies(storage: InMemoryKeyValueStore = InMemoryKeyValueStore()) -> PreferencesDependencies {
    let settings = AppSettings(storage: storage)
    return PreferencesDependencies(
        settings: settings,
        themeController: ThemeController(settings: settings),
        localizationController: LocalizationController(settings: settings),
        launchShortcutController: LaunchShortcutController(
            settings: settings,
            hotKeyRegistrar: TestHotKeyRegistrar(),
            frontmostApplicationObserver: TestFrontmostApplicationObserver(),
            frontmostApplicationProvider: { nil }
        ),
        updateManager: makeUpdateManager(settings: settings, driver: StubSparkleDriver(canCheckForUpdates: true)),
        specialFoldersStore: SpecialFoldersStore(storage: storage),
        permissionCoordinator: PermissionGuidanceCoordinator(probePaths: ["/nonexistent"], canOpen: { _ in false }, fileExists: { _ in false })
    )
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

private final class TestFrontmostApplicationObserver: FrontmostApplicationObserving {
    private(set) var isObserving = false
    private var handler: ((String?) -> Void)?

    func startObserving(handler: @escaping (String?) -> Void) {
        isObserving = true
        self.handler = handler
    }

    func stopObserving() {
        isObserving = false
        handler = nil
    }

    func activate(_ bundleIdentifier: String?) {
        handler?(bundleIdentifier)
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
