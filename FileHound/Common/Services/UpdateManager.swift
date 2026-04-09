import AppKit

#if SPARKLE_ENABLED
import Sparkle
#endif

final class UpdateManager: NSObject {
    static let shared = UpdateManager()

    #if SPARKLE_ENABLED
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    #endif

    @objc
    func checkForUpdates(_ sender: Any?) {
        #if SPARKLE_ENABLED
        updaterController.checkForUpdates(sender)
        #endif
    }

    func shouldCheckOnLaunch() -> Bool {
        AppSettings.shared.updateCheckPolicy == .onLaunch
    }
}
