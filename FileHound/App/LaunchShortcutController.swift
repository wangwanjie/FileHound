import AppKit
import Carbon.HIToolbox

protocol LaunchShortcutControlling: AnyObject {
    func configure(action: @escaping () -> Void)
    func reload()
}

protocol HotKeyRegistering: AnyObject {
    @discardableResult
    func register(shortcut: KeyboardShortcut, handler: @escaping () -> Void) -> Bool
    func unregister()
}

/// 观察最前端 App 切换；回调参数为新激活 App 的 bundle identifier
protocol FrontmostApplicationObserving: AnyObject {
    func startObserving(handler: @escaping (String?) -> Void)
    func stopObserving()
}

final class LaunchShortcutController: LaunchShortcutControlling {
    static let finderBundleIdentifier = "com.apple.finder"
    static let shared = LaunchShortcutController(settingsProvider: { AppSettings.shared })

    private let settingsProvider: () -> AppSettings
    private let hotKeyRegistrar: HotKeyRegistering
    private let frontmostApplicationObserver: FrontmostApplicationObserving
    private let frontmostApplicationProvider: () -> String?
    private var action: (() -> Void)?

    init(
        settings: AppSettings,
        hotKeyRegistrar: HotKeyRegistering = CarbonHotKeyRegistrar(),
        frontmostApplicationObserver: FrontmostApplicationObserving = WorkspaceFrontmostApplicationObserver(),
        frontmostApplicationProvider: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) {
        self.settingsProvider = { settings }
        self.hotKeyRegistrar = hotKeyRegistrar
        self.frontmostApplicationObserver = frontmostApplicationObserver
        self.frontmostApplicationProvider = frontmostApplicationProvider
    }

    private init(
        settingsProvider: @escaping () -> AppSettings,
        hotKeyRegistrar: HotKeyRegistering = CarbonHotKeyRegistrar(),
        frontmostApplicationObserver: FrontmostApplicationObserving = WorkspaceFrontmostApplicationObserver(),
        frontmostApplicationProvider: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) {
        self.settingsProvider = settingsProvider
        self.hotKeyRegistrar = hotKeyRegistrar
        self.frontmostApplicationObserver = frontmostApplicationObserver
        self.frontmostApplicationProvider = frontmostApplicationProvider
    }

    deinit {
        hotKeyRegistrar.unregister()
        frontmostApplicationObserver.stopObserving()
    }

    func configure(action: @escaping () -> Void) {
        self.action = action
        reload()
    }

    func reload() {
        hotKeyRegistrar.unregister()
        frontmostApplicationObserver.stopObserving()

        let settings = settingsProvider()

        guard let shortcut = KeyboardShortcut(serialized: settings.launchShortcut) else {
            return
        }

        switch settings.activationMode {
        case .global:
            _ = hotKeyRegistrar.register(shortcut: shortcut) { [weak self] in
                self?.action?()
            }
        case .finderOnly:
            // 全局事件监听需要辅助功能权限；改为仅在访达位于最前时注册 Carbon 热键，无需额外授权且不会把按键传给访达
            let updateRegistration: (String?) -> Void = { [weak self] bundleIdentifier in
                guard let self else { return }
                if bundleIdentifier == Self.finderBundleIdentifier {
                    _ = self.hotKeyRegistrar.register(shortcut: shortcut) { [weak self] in
                        self?.action?()
                    }
                } else {
                    self.hotKeyRegistrar.unregister()
                }
            }
            frontmostApplicationObserver.startObserving(handler: updateRegistration)
            updateRegistration(frontmostApplicationProvider())
        }
    }
}

private final class CarbonHotKeyRegistrar: HotKeyRegistering {
    private static let signature = OSType(0x46484F54)

    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?

    @discardableResult
    func register(shortcut: KeyboardShortcut, handler: @escaping () -> Void) -> Bool {
        unregister()
        self.handler = handler

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else {
                return noErr
            }

            let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
            registrar.handler?()
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else {
            unregister()
            return false
        }

        var hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(shortcut.keyCode))
        let registerStatus = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            unregister()
            return false
        }

        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        hotKeyRef = nil
        handlerRef = nil
        handler = nil
    }
}

private final class WorkspaceFrontmostApplicationObserver: FrontmostApplicationObserving {
    private var observerToken: NSObjectProtocol?

    func startObserving(handler: @escaping (String?) -> Void) {
        stopObserving()
        observerToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            handler(application?.bundleIdentifier)
        }
    }

    func stopObserving() {
        if let observerToken {
            NSWorkspace.shared.notificationCenter.removeObserver(observerToken)
        }
        observerToken = nil
    }
}

private extension KeyboardShortcut {
    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0
        if modifierFlags.contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if modifierFlags.contains(.control) {
            flags |= UInt32(controlKey)
        }
        if modifierFlags.contains(.option) {
            flags |= UInt32(optionKey)
        }
        if modifierFlags.contains(.shift) {
            flags |= UInt32(shiftKey)
        }
        return flags
    }
}
