import AppKit
import Testing
@testable import FileHound

struct PermissionGuidanceTests {
    @Test
    func fullDiskAccessIsGrantedWhenAnyProtectedPathOpens() {
        let denied = PermissionGuidanceCoordinator(probePaths: ["/a", "/b"], canOpen: { _ in false }, fileExists: { _ in false })
        #expect(denied.currentState() == PermissionState(fullDiskAccessGranted: false, helperInstalled: false))
        #expect(denied.currentState().bannerStyle == .warning)

        let granted = PermissionGuidanceCoordinator(probePaths: ["/a", "/b"], canOpen: { $0 == "/b" }, fileExists: { _ in false })
        #expect(granted.currentState().fullDiskAccessGranted)
        #expect(granted.currentState().bannerStyle == .normal)
    }

    @Test
    func helperIsInstalledWhenLaunchDaemonPlistExists() {
        let coordinator = PermissionGuidanceCoordinator(
            probePaths: [],
            canOpen: { _ in false },
            fileExists: { $0 == PermissionGuidanceCoordinator.helperLaunchDaemonPath }
        )
        #expect(coordinator.currentState().helperInstalled)
        #expect(coordinator.currentState().helperText == L10n.string("preferences.permissions.helper.installed"))
    }

    @Test
    func probePathsIncludeUserAndSystemTCCDatabases() {
        let paths = PermissionGuidanceCoordinator.fullDiskAccessProbePaths(homeDirectory: "/Users/demo")
        #expect(paths.contains("/Users/demo/Library/Application Support/com.apple.TCC/TCC.db"))
        #expect(paths.contains("/Library/Application Support/com.apple.TCC/TCC.db"))
        #expect(PermissionGuidanceCoordinator.canOpenForReading("/definitely/missing/file") == false)
        #expect(PermissionGuidanceCoordinator.canOpenForReading("/etc/hosts"))
    }

    @MainActor
    @Test
    func paneShowsStateRefreshesAndOpensSettings() {
        var granted = false
        var openedURL: URL?
        let coordinator = PermissionGuidanceCoordinator(probePaths: ["/x"], canOpen: { _ in granted }, fileExists: { _ in false })
        let controller = PermissionsPreferencesViewController(coordinator: coordinator, openSettings: { openedURL = $0 })
        _ = controller.view

        #expect(controller.debugFullDiskAccessText == L10n.string("preferences.permissions.fda.denied"))
        #expect(controller.debugExplanationHidden == false)

        granted = true
        controller.refresh(nil)
        #expect(controller.debugFullDiskAccessText == L10n.string("preferences.permissions.fda.granted"))
        #expect(controller.debugExplanationHidden)

        controller.openFullDiskAccessSettings(nil)
        #expect(openedURL == PermissionGuidanceCoordinator.fullDiskAccessSettingsURL)
    }

    @MainActor
    @Test
    func preferencesWindowIncludesPermissionsTab() {
        let root = PreferencesRootViewController(initialSegment: 4)
        _ = root.view
        #expect(root.debugSegmentLabels.last == L10n.string("preferences.tab.permissions"))
        #expect(root.debugActiveController is PermissionsPreferencesViewController)
    }
}
