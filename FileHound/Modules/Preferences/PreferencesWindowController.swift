import AppKit
import SnapKit

/// 偏好设置各页面的依赖。生产环境用 `.live`（各单例）；测试注入内存存储与假的 UpdateManager，
/// 避免读写用户真实 MMKV、创建真实的 Sparkle 控制器或注册全局热键
struct PreferencesDependencies {
    var settings: AppSettings
    var themeController: ThemeController
    var localizationController: LocalizationController
    var launchShortcutController: LaunchShortcutControlling
    var updateManager: UpdateManager
    var specialFoldersStore: SpecialFoldersStore
    var permissionCoordinator: PermissionGuidanceCoordinator

    static var live: PreferencesDependencies {
        PreferencesDependencies(
            settings: .shared,
            themeController: .shared,
            localizationController: .shared,
            launchShortcutController: LaunchShortcutController.shared,
            updateManager: .shared,
            specialFoldersStore: .shared,
            permissionCoordinator: PermissionGuidanceCoordinator()
        )
    }

    /// 按分段顺序（通用、搜索、外观、更新、权限）创建各页面
    func makeContentControllers() -> [NSViewController] {
        [
            GeneralPreferencesViewController(settings: settings, launchShortcutController: launchShortcutController),
            SearchPreferencesViewController(settings: settings, specialFoldersStore: specialFoldersStore),
            AppearancePreferencesViewController(
                settings: settings,
                themeController: themeController,
                localizationController: localizationController
            ),
            UpdatePreferencesViewController(settings: settings, updateManager: updateManager),
            PermissionsPreferencesViewController(coordinator: permissionCoordinator)
        ]
    }
}

final class PreferencesWindowController: NSWindowController {
    /// 延迟到首次创建页面时才求值，避免构造窗口控制器时就创建各单例。
    /// 默认值不能省：`PreferencesWindowController()` 会优先匹配继承来的无参 `NSWindowController.init()`，
    /// 不经过下面的便利构造器，此时也必须能拿到生产依赖
    private var dependenciesProvider: () -> PreferencesDependencies = { .live }
    private lazy var dependencies: PreferencesDependencies = dependenciesProvider()

    convenience init(dependencies dependenciesProvider: @escaping @autoclosure () -> PreferencesDependencies = .live) {
        self.init(window: nil)
        self.dependenciesProvider = dependenciesProvider
        installRootViewController(initialSegment: 2)
    }

    func show(segment initialSegment: Int? = nil, sender: Any? = nil) {
        if let initialSegment {
            installRootViewController(initialSegment: initialSegment)
        } else if window?.contentViewController == nil {
            installRootViewController(initialSegment: 0)
        }

        showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        (window?.contentViewController as? PreferencesRootViewController)?.refreshWindowSize(animated: false)
    }

    func reloadLocalizedContent() {
        guard window != nil else {
            return
        }

        installRootViewController(initialSegment: selectedSegmentIndex)
        (window?.contentViewController as? PreferencesRootViewController)?.refreshWindowSize(animated: false)
    }

    private var selectedSegmentIndex: Int {
        (window?.contentViewController as? PreferencesRootViewController)?.selectedSegmentIndex ?? 0
    }

    private func installRootViewController(initialSegment: Int) {
        let rootViewController = PreferencesRootViewController(
            initialSegment: initialSegment,
            contentControllers: dependencies.makeContentControllers()
        )

        if let window {
            window.contentViewController = rootViewController
            window.title = L10n.string("preferences.window.title")
            return
        }

        let window = NSWindow(contentViewController: rootViewController)
        window.setContentSize(NSSize(width: PreferencesLayout.windowWidth, height: PreferencesLayout.minWindowHeight))
        window.title = L10n.string("preferences.window.title")
        window.center()
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.styleMask.remove(.resizable)
        // 窗口由本控制器持有并可反复显示；关闭时不能让 AppKit 额外 release（ARC 下会造成过度释放）
        window.isReleasedWhenClosed = false
        self.window = window
    }
}

final class PreferencesSectionView: NSView {
    private let cardView = NSView()
    let contentGuide = NSView()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.textColor = .secondaryLabelColor
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 14
        cardView.layer?.borderWidth = 1

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(cardView)
        cardView.addSubview(contentGuide)

        titleLabel.snp.makeConstraints { make in
            make.leading.top.equalToSuperview()
        }
        subtitleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
        }
        cardView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(subtitleLabel.snp.bottom).offset(20)
        }
        contentGuide.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(18)
        }

        applyCardAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCardAppearance()
    }

    private func applyCardAppearance(resolvedAgainst appearance: NSAppearance? = nil) {
        let resolvedAppearance = appearance ?? effectiveAppearance
        cardView.layer?.borderColor = NSColor.fhHairline(for: resolvedAppearance, alpha: 0.8).fhResolvedCGColor(for: resolvedAppearance)
        cardView.layer?.backgroundColor = NSColor.fhCardSurface(for: resolvedAppearance, alpha: 0.94).fhResolvedCGColor(for: resolvedAppearance)
    }

    #if DEBUG
    var debugHasCardBackground: Bool {
        cardView.layer?.cornerRadius == 14 && cardView.layer?.backgroundColor != nil
    }

    func debugCardBackgroundHex(for appearanceName: NSAppearance.Name) -> String {
        let appearance = NSAppearance(named: appearanceName)
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)!
        return NSColor.fhCardSurface(for: appearance, alpha: 0.94).fhResolvedHex(for: appearanceName)
    }
    #endif
}
