import XCTest
@testable import FileHound

final class SearchSessionTests: XCTestCase {
    func testRunPreviewStreamsMatches() async throws {
        let session = SearchSession()

        let summary = try await session.runPreview(paths: ["/tmp/demo.txt"], contentNeedle: "demo")

        XCTAssertFalse(summary.isCancelled)
        XCTAssertEqual(summary.results.count, 1)
        XCTAssertEqual(summary.results.first?.matchReason, "内容命中")
        XCTAssertEqual(summary.results.first?.previewSnippet, "demo")
    }
}
