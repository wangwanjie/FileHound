import XCTest
@testable import FileHound

final class SearchPlanBuilderTests: XCTestCase {
    func testBuildUsesPrivilegedProviderWhenContentScanRequiredInPrivilegedMode() {
        let compiledQuery = CompiledQuery(
            rootPaths: ["/tmp"],
            rootGroup: .rule(.contentContains("needle")),
            requiresContentScan: true,
            excludedPathFragments: []
        )
        let builder = SearchPlanBuilder()

        let plan = builder.build(from: compiledQuery, mode: .privileged)

        XCTAssertEqual(plan.providerKind, .privileged)
        XCTAssertTrue(plan.shouldScanContents)
    }
}
