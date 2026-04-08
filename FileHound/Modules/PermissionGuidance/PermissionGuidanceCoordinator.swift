import Foundation

enum PermissionBannerStyle: Equatable, Sendable {
    case normal
    case warning
}

struct PermissionState: Equatable, Sendable {
    let fullDiskAccessGranted: Bool
    let helperInstalled: Bool
    let helperReachable: Bool

    var bannerStyle: PermissionBannerStyle {
        fullDiskAccessGranted && helperReachable ? .normal : .warning
    }

    var summary: String {
        let fda = fullDiskAccessGranted ? "已授权" : "未授权"
        let helper = helperReachable ? "可用" : "不可用"
        return "Full Disk Access: \(fda) | Helper: \(helper)"
    }
}

final class PermissionGuidanceCoordinator {
    func currentState() -> PermissionState {
        PermissionState(
            fullDiskAccessGranted: hasFullDiskAccess(),
            helperInstalled: false,
            helperReachable: false
        )
    }

    private func hasFullDiskAccess() -> Bool {
        FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }
}
