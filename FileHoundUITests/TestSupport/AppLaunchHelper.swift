import AppKit
import XCTest

enum AppLaunchHelper {
    static func terminateRunningInstances(bundleIdentifier: String) {
        let deadline = Date().addingTimeInterval(5)
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)

        for app in runningApps {
            if app.isTerminated == false {
                app.terminate()
            }
        }

        while Date() < deadline {
            let remaining = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            if remaining.isEmpty {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let remaining = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in remaining where app.isTerminated == false {
            app.forceTerminate()
        }

        let forceDeadline = Date().addingTimeInterval(2)
        while Date() < forceDeadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    static func prepareForLaunch(_ app: XCUIApplication) {
        terminateRunningInstances(bundleIdentifier: "cn.vanjay.FileHound")
        if app.state != .notRunning {
            app.terminate()
        }
    }
}
