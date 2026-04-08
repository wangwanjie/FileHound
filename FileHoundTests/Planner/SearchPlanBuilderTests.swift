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

    func testBuildUsesLocalProviderInStandardMode() {
        let compiledQuery = CompiledQuery(
            rootPaths: ["/tmp"],
            rootGroup: .rule(.nameContains("log")),
            requiresContentScan: false,
            excludedPathFragments: []
        )
        let builder = SearchPlanBuilder()

        let plan = builder.build(from: compiledQuery, mode: .standard)

        XCTAssertEqual(plan.providerKind, .local)
        XCTAssertFalse(plan.shouldScanContents)
    }

    func testBuildNormalizesGroupAndCarriesExclusions() {
        let compiledQuery = CompiledQuery(
            rootPaths: ["/Users/example"],
            rootGroup: .all([
                .rule(.nameContains("report")),
                .exclude(.pathContains("tmp"))
            ]),
            requiresContentScan: false,
            excludedPathFragments: ["tmp"]
        )
        let builder = SearchPlanBuilder()

        let plan = builder.build(from: compiledQuery, mode: .standard)

        XCTAssertEqual(plan.rootPaths, ["/Users/example"])
        XCTAssertEqual(plan.rootGroup, .all([.rule(.nameContains("report"))]))
        XCTAssertEqual(plan.excludedPathFragments, ["tmp"])
    }

    func testProvidersExposeConsistentKind() {
        XCTAssertEqual(LocalFilesystemProvider().kind, .local)
        XCTAssertEqual(PrivilegedFilesystemProvider().kind, .privileged)
    }
}
