import Foundation
import Testing
@testable import FileHound

struct UpdateManagerTests {
    @Test
    func canCheckForUpdatesRequiresVersionMetadataFeedAndRuntimeSupport() {
        let manager = UpdateManager(
            settings: AppSettings(storage: InMemoryKeyValueStore()),
            bundleInfo: .init(
                shortVersion: "1.1.1",
                buildVersion: "3",
                feedURL: "https://example.com/appcast-arm64.xml",
                publicKey: "test-public-key"
            ),
            sparkleDriver: StubSparkleDriver(canCheckForUpdates: true)
        )

        #expect(manager.canCheckForUpdates == true)
        #expect(manager.unavailableReason == nil)
    }

    @Test
    func canCheckForUpdatesIsFalseWhenFeedMetadataIsMissing() {
        let manager = UpdateManager(
            settings: AppSettings(storage: InMemoryKeyValueStore()),
            bundleInfo: .init(
                shortVersion: "1.1.1",
                buildVersion: "3",
                feedURL: nil,
                publicKey: "test-public-key"
            ),
            sparkleDriver: StubSparkleDriver(canCheckForUpdates: true)
        )

        #expect(manager.canCheckForUpdates == false)
        #expect(manager.unavailableReason != nil)
    }

    @Test
    func shouldCheckOnLaunchRespectsPolicy() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.updateCheckPolicy = .manualOnly
        let manager = UpdateManager(
            settings: settings,
            bundleInfo: .init(
                shortVersion: "1.1.1",
                buildVersion: "3",
                feedURL: "https://example.com/appcast-arm64.xml",
                publicKey: "test-public-key"
            ),
            sparkleDriver: StubSparkleDriver(canCheckForUpdates: true)
        )

        #expect(manager.shouldCheckOnLaunch() == false)

        settings.updateCheckPolicy = .onLaunch
        #expect(manager.shouldCheckOnLaunch() == true)
    }

    @Test
    func checkForUpdatesStartsUpdaterAndForwardsSenderWhenAvailable() {
        let driver = StubSparkleDriver(canCheckForUpdates: true)
        let manager = UpdateManager(
            settings: AppSettings(storage: InMemoryKeyValueStore()),
            bundleInfo: .init(
                shortVersion: "1.1.1",
                buildVersion: "3",
                feedURL: "https://example.com/appcast-arm64.xml",
                publicKey: "test-public-key"
            ),
            sparkleDriver: driver
        )
        let sender = NSObject()

        manager.checkForUpdates(sender)

        #expect(driver.startCalls == 1)
        #expect(driver.checkCalls == 1)
        #expect(driver.lastSender === sender)
    }

    @Test
    func configureForLaunchAppliesPolicyToSparkleDriver() {
        let storage = InMemoryKeyValueStore()
        let settings = AppSettings(storage: storage)
        settings.updateCheckPolicy = .dailyAutomatic
        settings.autoDownloadUpdates = true
        let driver = StubSparkleDriver(canCheckForUpdates: true)
        let manager = UpdateManager(
            settings: settings,
            bundleInfo: .init(
                shortVersion: "1.1.1",
                buildVersion: "3",
                feedURL: "https://example.com/appcast-arm64.xml",
                publicKey: "test-public-key"
            ),
            sparkleDriver: driver
        )

        manager.configureForLaunch()

        #expect(driver.startCalls == 1)
        #expect(driver.appliedPolicies == [.dailyAutomatic])
        #expect(driver.appliedAutoDownloadFlags == [true])
    }
}

private final class StubSparkleDriver: SparkleUpdateDriving {
    let canCheckForUpdates: Bool
    var startCalls = 0
    var checkCalls = 0
    var lastSender: AnyObject?
    var appliedPolicies: [UpdateCheckPolicy] = []
    var appliedAutoDownloadFlags: [Bool] = []

    init(canCheckForUpdates: Bool) {
        self.canCheckForUpdates = canCheckForUpdates
    }

    func startUpdaterIfNeeded() {
        startCalls += 1
    }

    func checkForUpdates(_ sender: Any?) {
        checkCalls += 1
        lastSender = sender as AnyObject?
    }

    func apply(policy: UpdateCheckPolicy, automaticallyDownloadsUpdates: Bool) {
        appliedPolicies.append(policy)
        appliedAutoDownloadFlags.append(automaticallyDownloadsUpdates)
    }
}
