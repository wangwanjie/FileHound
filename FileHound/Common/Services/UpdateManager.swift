import AppKit

#if SPARKLE_ENABLED
import Sparkle
#endif

final class UpdateManager: NSObject {
    static let shared = UpdateManager()

    #if SPARKLE_ENABLED
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var didStartUpdater = false
    #endif

    var canCheckForUpdates: Bool {
        hasRequiredVersionMetadata && hasSparkleFeedConfiguration
    }

    @objc
    func checkForUpdates(_ sender: Any?) {
        #if SPARKLE_ENABLED
        guard canCheckForUpdates else {
            return
        }

        startUpdaterIfNeeded()
        updaterController.checkForUpdates(sender)
        #endif
    }

    func shouldCheckOnLaunch() -> Bool {
        AppSettings.shared.updateCheckPolicy == .onLaunch && canCheckForUpdates
    }

    private var hasRequiredVersionMetadata: Bool {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return shortVersion?.isEmpty == false && buildVersion?.isEmpty == false
    }

    private var hasSparkleFeedConfiguration: Bool {
        let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return feedURL?.isEmpty == false && publicKey?.isEmpty == false
    }

    #if SPARKLE_ENABLED
    private func startUpdaterIfNeeded() {
        guard didStartUpdater == false else {
            return
        }

        updaterController.startUpdater()
        didStartUpdater = true
    }
    #endif
}
