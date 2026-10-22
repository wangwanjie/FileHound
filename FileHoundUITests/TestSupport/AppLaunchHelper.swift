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

    /// 在第一条规则中填入值，让「查找」按钮可用。
    /// --uitesting 使用独立的空白设置存储，不会恢复上次会话的规则值，直接点「查找」不会开始搜索
    static func enterRuleValue(_ value: String, in app: XCUIApplication) {
        let valueField = app.textFields["SearchRuleValueField"]
        XCTAssertTrue(valueField.waitForExistence(timeout: 3))
        valueField.click()
        valueField.typeKey("a", modifierFlags: .command)
        valueField.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        valueField.typeText(value)
    }

    static func prepareForLaunch(_ app: XCUIApplication) {
        terminateRunningInstances(bundleIdentifier: "cn.vanjay.FileHound")
        if app.state != .notRunning {
            app.terminate()
        }
    }
}
