import Foundation

enum PermissionBannerStyle: Equatable, Sendable {
    case normal
    case warning
}

struct PermissionState: Equatable, Sendable {
    let fullDiskAccessGranted: Bool
    let helperInstalled: Bool

    /// Helper 为可选增强，只有完全磁盘访问缺失时才需要提醒
    var bannerStyle: PermissionBannerStyle {
        fullDiskAccessGranted ? .normal : .warning
    }

    var fullDiskAccessText: String {
        L10n.string(fullDiskAccessGranted ? "preferences.permissions.fda.granted" : "preferences.permissions.fda.denied")
    }

    var helperText: String {
        L10n.string(helperInstalled ? "preferences.permissions.helper.installed" : "preferences.permissions.helper.not_installed")
    }
}

final class PermissionGuidanceCoordinator {
    static let helperLaunchDaemonPath = "/Library/LaunchDaemons/cn.vanjay.FileHound.Helper.plist"
    static let fullDiskAccessSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// 受 TCC「完全磁盘访问」保护的文件；能实际打开其中任意一个即视为已授权
    static func fullDiskAccessProbePaths(homeDirectory: String = NSHomeDirectory()) -> [String] {
        [
            "\(homeDirectory)/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "\(homeDirectory)/Library/Safari/Bookmarks.plist",
            "\(homeDirectory)/Library/Mail"
        ]
    }

    private let probePaths: [String]
    private let canOpen: (String) -> Bool
    private let fileExists: (String) -> Bool

    init(
        probePaths: [String] = PermissionGuidanceCoordinator.fullDiskAccessProbePaths(),
        canOpen: @escaping (String) -> Bool = PermissionGuidanceCoordinator.canOpenForReading,
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.probePaths = probePaths
        self.canOpen = canOpen
        self.fileExists = fileExists
    }

    func currentState() -> PermissionState {
        PermissionState(
            fullDiskAccessGranted: probePaths.contains(where: canOpen),
            helperInstalled: fileExists(Self.helperLaunchDaemonPath)
        )
    }

    /// access() 只检查 POSIX 权限，TCC 拦截要真正 open 才能体现
    static func canOpenForReading(_ path: String) -> Bool {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else {
            return false
        }
        close(descriptor)
        return true
    }
}
