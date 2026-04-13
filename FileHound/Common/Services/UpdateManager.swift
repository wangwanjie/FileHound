import AppKit

#if SPARKLE_ENABLED
import Sparkle
#endif

protocol SparkleUpdateDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    func startUpdaterIfNeeded()
    func checkForUpdates(_ sender: Any?)
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

    private let settings: AppSettings
    private let bundleInfo: UpdateBundleInfo
    private let sparkleDriver: SparkleUpdateDriving

    init(
        settings: AppSettings = .shared,
        bundleInfo: UpdateBundleInfo = .main,
        sparkleDriver: SparkleUpdateDriving = UpdateManager.makeDefaultSparkleDriver()
    ) {
        self.settings = settings
        self.bundleInfo = bundleInfo
        self.sparkleDriver = sparkleDriver
        super.init()
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

    func configureForLaunch() {
        sparkleDriver.startUpdaterIfNeeded()
        sparkleDriver.apply(
            policy: settings.updateCheckPolicy,
            automaticallyDownloadsUpdates: settings.autoDownloadUpdates
        )
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
    func apply(policy: UpdateCheckPolicy, automaticallyDownloadsUpdates: Bool) {}
}

#if SPARKLE_ENABLED
private final class SparkleDriver: NSObject, SparkleUpdateDriving {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private let updaterSettings = SPUUpdaterSettings(hostBundle: .main)
    private var didStartUpdater = false

    var canCheckForUpdates: Bool {
        true
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

    func apply(policy: UpdateCheckPolicy, automaticallyDownloadsUpdates: Bool) {
        switch policy {
        case .onLaunch, .manualOnly:
            updaterSettings.automaticallyChecksForUpdates = false
        case .dailyAutomatic:
            updaterSettings.automaticallyChecksForUpdates = true
            updaterSettings.updateCheckInterval = 24 * 60 * 60
        }
        updaterSettings.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
    }
}
#endif
