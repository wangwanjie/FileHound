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

protocol ShortcutMonitoring: AnyObject {
    func startMonitoring(handler: @escaping (KeyboardShortcut) -> Void)
    func stopMonitoring()
}

final class LaunchShortcutController: LaunchShortcutControlling {
    static let shared = LaunchShortcutController(settingsProvider: { AppSettings.shared })

    private let settingsProvider: () -> AppSettings
    private let hotKeyRegistrar: HotKeyRegistering
    private let shortcutMonitor: ShortcutMonitoring
    private let frontmostApplicationProvider: () -> String?
    private var action: (() -> Void)?

    init(
        settings: AppSettings,
        hotKeyRegistrar: HotKeyRegistering = CarbonHotKeyRegistrar(),
        shortcutMonitor: ShortcutMonitoring = NSEventShortcutMonitor(),
        frontmostApplicationProvider: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) {
        self.settingsProvider = { settings }
        self.hotKeyRegistrar = hotKeyRegistrar
        self.shortcutMonitor = shortcutMonitor
        self.frontmostApplicationProvider = frontmostApplicationProvider
    }

    private init(
        settingsProvider: @escaping () -> AppSettings,
        hotKeyRegistrar: HotKeyRegistering = CarbonHotKeyRegistrar(),
        shortcutMonitor: ShortcutMonitoring = NSEventShortcutMonitor(),
        frontmostApplicationProvider: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) {
        self.settingsProvider = settingsProvider
        self.hotKeyRegistrar = hotKeyRegistrar
        self.shortcutMonitor = shortcutMonitor
        self.frontmostApplicationProvider = frontmostApplicationProvider
    }

    deinit {
        hotKeyRegistrar.unregister()
        shortcutMonitor.stopMonitoring()
    }

    func configure(action: @escaping () -> Void) {
        self.action = action
        reload()
    }

    func reload() {
        hotKeyRegistrar.unregister()
        shortcutMonitor.stopMonitoring()

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
            shortcutMonitor.startMonitoring { [weak self] observedShortcut in
                guard
                    let self,
                    observedShortcut == shortcut,
                    self.frontmostApplicationProvider() == "com.apple.finder"
                else {
                    return
                }

                self.action?()
            }
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

private final class NSEventShortcutMonitor: ShortcutMonitoring {
    private var monitorToken: Any?

    func startMonitoring(handler: @escaping (KeyboardShortcut) -> Void) {
        stopMonitoring()
        monitorToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard let shortcut = KeyboardShortcut.capture(from: event) else {
                return
            }
            handler(shortcut)
        }
    }

    func stopMonitoring() {
        if let monitorToken {
            NSEvent.removeMonitor(monitorToken)
        }
        monitorToken = nil
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
