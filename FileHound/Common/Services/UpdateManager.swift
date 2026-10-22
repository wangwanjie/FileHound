import AppKit

#if SPARKLE_ENABLED
import Sparkle
#endif

protocol SparkleUpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    func startUpdaterIfNeeded()
    /// 用户主动检查：显示进度窗与「已是最新」等结果弹窗，只用于菜单 / 按钮
    func checkForUpdates(_ sender: Any?)
    /// 后台静默检查：只有发现新版本时才提示，用于启动时的自动检查
    func checkForUpdatesInBackground()
    func apply(policy: UpdateCheckPolicy, automaticallyDownloadsUpdates: Bool)
}

struct UpdateBundleInfo {
    let shortVersion: String?
    let buildVersion: String?
    let feedURL: String?
    let publicKey: String?

    static let main = UpdateBundleInfo(bundle: .main)

    init(shortVersion: String?, buildVersion: String?, feedURL: String?, publicKey: String?) {
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.feedURL = feedURL
        self.publicKey = publicKey
    }

    init(bundle: Bundle) {
        self.init(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            feedURL: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        )
    }
}

final class UpdateManager: NSObject {
    static let shared = UpdateManager()

    /// 按架构区分的 appcast 地址前缀（与 build_dmg.sh / generate_appcast.sh 产出的文件名一致）
    static let appcastBaseURLString = "https://raw.githubusercontent.com/wangwanjie/FileHound/main/"

    /// 当前构建是否允许自动检查（启动检查 / 每日定时检查）。
    /// Debug 构建的版本号通常与正式版相同或更旧，自动检查正式更新源会不断弹出「发现新版本」打扰开发调试，
    /// 因此 Debug 下只保留用户手动检查
    static var isAutomaticCheckingAllowedInThisBuild: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    private let settingsProvider: () -> AppSettings
    private let bundleInfo: UpdateBundleInfo
    private let sparkleDriver: SparkleUpdateDriving
    private let allowsAutomaticChecks: Bool

    init(
        settings: AppSettings? = nil,
        bundleInfo: UpdateBundleInfo = .main,
        sparkleDriver: SparkleUpdateDriving = UpdateManager.makeDefaultSparkleDriver(),
        allowsAutomaticChecks: Bool = UpdateManager.isAutomaticCheckingAllowedInThisBuild
    ) {
        if let settings {
            self.settingsProvider = { settings }
        } else {
            self.settingsProvider = { AppSettings.shared }
        }
        self.bundleInfo = bundleInfo
        self.sparkleDriver = sparkleDriver
        self.allowsAutomaticChecks = allowsAutomaticChecks
        super.init()
    }

    /// 按 CPU 架构返回对应的 appcast 地址；未知架构返回 nil（交给 Info.plist 中的 SUFeedURL）
    static func feedURLString(forArchitecture architecture: String) -> String? {
        switch architecture {
        case "arm64", "x86_64":
            return appcastBaseURLString + "appcast-\(architecture).xml"
        default:
            return nil
        }
    }

    /// 当前编译架构对应的 appcast 地址。运行时选择 feed，即使未经打包脚本覆盖 Info.plist，各架构也能拿到正确的更新源
    static var currentArchitectureFeedURLString: String? {
        #if arch(arm64)
        return feedURLString(forArchitecture: "arm64")
        #elseif arch(x86_64)
        return feedURLString(forArchitecture: "x86_64")
        #else
        return nil
        #endif
    }

    var canCheckForUpdates: Bool {
        unavailableReason == nil
    }

    var unavailableReason: String? {
        guard hasRequiredVersionMetadata else {
            return L10n.string("preferences.update.feed_missing")
        }

        guard hasSparkleFeedConfiguration else {
            return L10n.string("preferences.update.feed_missing")
        }

        guard sparkleDriver.canCheckForUpdates else {
            return L10n.string("preferences.update.feed_missing")
        }

        return nil
    }

    @objc
    func checkForUpdates(_ sender: Any?) {
        guard canCheckForUpdates else {
            return
        }

        sparkleDriver.startUpdaterIfNeeded()
        sparkleDriver.checkForUpdates(sender)
    }

    /// 把偏好中的更新策略应用到 Sparkle；偏好设置修改后也调用此方法立即生效
    func applySettings() {
        sparkleDriver.apply(
            policy: settings.updateCheckPolicy,
            automaticallyDownloadsUpdates: settings.autoDownloadUpdates
        )

        // 「每天自动检查」依赖 Sparkle 的定时器，只有 updater 启动后才会排期
        if settings.updateCheckPolicy == .dailyAutomatic, allowsAutomaticChecks, canCheckForUpdates {
            sparkleDriver.startUpdaterIfNeeded()
        }
    }

    /// 启动时调用：应用策略；策略为「启动时检查」时在后台静默检查，不弹「已是最新」
    func handleLaunch() {
        applySettings()

        guard allowsAutomaticChecks, shouldCheckOnLaunch() else {
            return
        }

        sparkleDriver.startUpdaterIfNeeded()
        sparkleDriver.checkForUpdatesInBackground()
    }

    func shouldCheckOnLaunch() -> Bool {
        settings.updateCheckPolicy == .onLaunch && canCheckForUpdates
    }

    private var hasRequiredVersionMetadata: Bool {
        bundleInfo.shortVersion?.isEmpty == false && bundleInfo.buildVersion?.isEmpty == false
    }

    private var hasSparkleFeedConfiguration: Bool {
        bundleInfo.feedURL?.isEmpty == false && bundleInfo.publicKey?.isEmpty == false
    }
}

private extension UpdateManager {
    var settings: AppSettings {
        settingsProvider()
    }

    static func makeDefaultSparkleDriver() -> SparkleUpdateDriving {
        #if SPARKLE_ENABLED
        SparkleDriver()
        #else
        DisabledSparkleDriver()
        #endif
    }
}

private final class DisabledSparkleDriver: SparkleUpdateDriving {
    let canCheckForUpdates = false

    func startUpdaterIfNeeded() {}
    func checkForUpdates(_ sender: Any?) {}
    func checkForUpdatesInBackground() {}
    func apply(policy: UpdateCheckPolicy, automaticallyDownloadsUpdates: Bool) {}
}

#if SPARKLE_ENABLED
private final class SparkleDriver: NSObject, SparkleUpdateDriving, SPUUpdaterDelegate {
    /// SPUStandardUpdaterController 对 updaterDelegate 是弱引用；delegate 就是本对象，
    /// 而本对象被 UpdateManager 强引用，因此生命周期覆盖整个 updater
    private var updaterController: SPUStandardUpdaterController!
    private var didStartUpdater = false

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        // 启动前 Sparkle 的 canCheckForUpdates 恒为 false，手动检查会先启动 updater，因此视为可用；
        // 启动后跟随 Sparkle（检查进行中时为 false，菜单随之禁用）
        guard didStartUpdater else {
            return true
        }
        return updaterController.updater.canCheckForUpdates
    }

    func startUpdaterIfNeeded() {
        guard didStartUpdater == false else {
            return
        }

        updaterController.startUpdater()
        didStartUpdater = true
    }

    func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }

    func apply(policy: UpdateCheckPolicy, automaticallyDownloadsUpdates: Bool) {
        // 直接设置 SPUUpdater 的属性：会写入用户默认值，并在 updater 已启动时自动重置检查周期，修改即时生效
        let updater = updaterController.updater
        switch policy {
        case .onLaunch, .manualOnly:
            updater.automaticallyChecksForUpdates = false
        case .dailyAutomatic:
            updater.automaticallyChecksForUpdates = true
            updater.updateCheckInterval = 24 * 60 * 60
        }
        updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
    }

    // MARK: - SPUUpdaterDelegate

    /// 运行时按架构选择 appcast，覆盖 Info.plist 中的 SUFeedURL
    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateManager.currentArchitectureFeedURLString
    }
}
#endif
