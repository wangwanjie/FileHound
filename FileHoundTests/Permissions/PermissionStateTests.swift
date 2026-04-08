import XCTest
@testable import FileHound

final class PermissionStateTests: XCTestCase {
    func testReportsFdaAndHelperStateSeparately() {
        let state = PermissionState(
            fullDiskAccessGranted: false,
            helperInstalled: true,
            helperReachable: false
        )

        XCTAssertEqual(state.bannerStyle, .warning)
        XCTAssertTrue(state.summary.contains("Full Disk Access"))
        XCTAssertTrue(state.summary.contains("Helper"))
    }
}
