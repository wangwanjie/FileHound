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
    func applySettingsStartsUpdaterForDailyAutomaticPolicy() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        settings.updateCheckPolicy = .dailyAutomatic
        settings.autoDownloadUpdates = true
        let driver = StubSparkleDriver(canCheckForUpdates: true)
        let manager = makeUpdateManager(settings: settings, driver: driver)

        manager.applySettings()

        // 「每天自动检查」必须启动 updater，Sparkle 才会排期定时检查
        #expect(driver.startCalls == 1)
        #expect(driver.appliedPolicies == [.dailyAutomatic])
        #expect(driver.appliedAutoDownloadFlags == [true])
        #expect(driver.checkCalls == 0)
        #expect(driver.backgroundCheckCalls == 0)
    }

    @Test
    func applySettingsDoesNotStartUpdaterForManualPolicies() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        let driver = StubSparkleDriver(canCheckForUpdates: true)
        let manager = makeUpdateManager(settings: settings, driver: driver)

        settings.updateCheckPolicy = .manualOnly
        manager.applySettings()
        settings.updateCheckPolicy = .onLaunch
        manager.applySettings()

        #expect(driver.startCalls == 0)
        #expect(driver.appliedPolicies == [.manualOnly, .onLaunch])
    }

    @Test
    func applySettingsDoesNotStartUpdaterWhenAutomaticChecksAreDisallowedOrUnavailable() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        settings.updateCheckPolicy = .dailyAutomatic
        let debugDriver = StubSparkleDriver(canCheckForUpdates: true)
        let unavailableDriver = StubSparkleDriver(canCheckForUpdates: false)

        makeUpdateManager(settings: settings, driver: debugDriver, allowsAutomaticChecks: false).applySettings()
        makeUpdateManager(settings: settings, driver: unavailableDriver).applySettings()

        #expect(debugDriver.startCalls == 0)
        #expect(debugDriver.appliedPolicies == [.dailyAutomatic])
        #expect(unavailableDriver.startCalls == 0)
    }

    @Test
    func handleLaunchChecksInBackgroundForOnLaunchPolicy() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        settings.updateCheckPolicy = .onLaunch
        let driver = StubSparkleDriver(canCheckForUpdates: true)
        let manager = makeUpdateManager(settings: settings, driver: driver)

        manager.handleLaunch()

        // 启动检查走后台静默检查，不能调用会弹进度窗 /「已是最新」的用户检查接口
        #expect(driver.appliedPolicies == [.onLaunch])
        #expect(driver.startCalls == 1)
        #expect(driver.backgroundCheckCalls == 1)
        #expect(driver.checkCalls == 0)
    }

    @Test
    func handleLaunchSkipsBackgroundCheckForOtherPoliciesAndDebugBuilds() {
        let manualSettings = AppSettings(storage: InMemoryKeyValueStore())
        manualSettings.updateCheckPolicy = .manualOnly
        let manualDriver = StubSparkleDriver(canCheckForUpdates: true)
        makeUpdateManager(settings: manualSettings, driver: manualDriver).handleLaunch()

        let onLaunchSettings = AppSettings(storage: InMemoryKeyValueStore())
        onLaunchSettings.updateCheckPolicy = .onLaunch
        let debugDriver = StubSparkleDriver(canCheckForUpdates: true)
        makeUpdateManager(settings: onLaunchSettings, driver: debugDriver, allowsAutomaticChecks: false).handleLaunch()

        #expect(manualDriver.backgroundCheckCalls == 0)
        #expect(manualDriver.startCalls == 0)
        #expect(debugDriver.backgroundCheckCalls == 0)
        #expect(debugDriver.startCalls == 0)
        #expect(debugDriver.appliedPolicies == [.onLaunch])
    }

    @Test
    func manualCheckStillWorksWhenAutomaticChecksAreDisallowed() {
        let driver = StubSparkleDriver(canCheckForUpdates: true)
        let manager = makeUpdateManager(
            settings: AppSettings(storage: InMemoryKeyValueStore()),
            driver: driver,
            allowsAutomaticChecks: false
        )

        manager.checkForUpdates(nil)

        #expect(driver.startCalls == 1)
        #expect(driver.checkCalls == 1)
    }

    @Test
    func debugBuildsDisallowAutomaticChecks() {
        #if DEBUG
        #expect(UpdateManager.isAutomaticCheckingAllowedInThisBuild == false)
        #else
        #expect(UpdateManager.isAutomaticCheckingAllowedInThisBuild == true)
        #endif
    }

    @Test
    func feedURLIsSelectedByArchitecture() {
        #expect(UpdateManager.feedURLString(forArchitecture: "arm64") == "https://raw.githubusercontent.com/wangwanjie/FileHound/main/appcast-arm64.xml")
        #expect(UpdateManager.feedURLString(forArchitecture: "x86_64") == "https://raw.githubusercontent.com/wangwanjie/FileHound/main/appcast-x86_64.xml")
        #expect(UpdateManager.feedURLString(forArchitecture: "ppc") == nil)

        #if arch(arm64)
        #expect(UpdateManager.currentArchitectureFeedURLString?.hasSuffix("/appcast-arm64.xml") == true)
        #elseif arch(x86_64)
        #expect(UpdateManager.currentArchitectureFeedURLString?.hasSuffix("/appcast-x86_64.xml") == true)
        #endif
    }
}

/// 构造使用内存设置与假 Sparkle 驱动的 UpdateManager，供各测试文件复用
func makeUpdateManager(
    settings: AppSettings,
    driver: StubSparkleDriver,
    allowsAutomaticChecks: Bool = true,
    feedURL: String? = "https://example.com/appcast-arm64.xml"
) -> UpdateManager {
    UpdateManager(
        settings: settings,
        bundleInfo: .init(
            shortVersion: "1.1.1",
            buildVersion: "3",
            feedURL: feedURL,
            publicKey: "test-public-key"
        ),
        sparkleDriver: driver,
        allowsAutomaticChecks: allowsAutomaticChecks
    )
}

final class StubSparkleDriver: SparkleUpdateDriving {
    let canCheckForUpdates: Bool
    var startCalls = 0
    var checkCalls = 0
    var backgroundCheckCalls = 0
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

    func checkForUpdatesInBackground() {
        backgroundCheckCalls += 1
    }

    func apply(policy: UpdateCheckPolicy, automaticallyDownloadsUpdates: Bool) {
        appliedPolicies.append(policy)
        appliedAutoDownloadFlags.append(automaticallyDownloadsUpdates)
    }
}
