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

    func testBuildDropsEmptyAnyGroupAfterExclusionNormalization() {
        let compiledQuery = CompiledQuery(
            rootPaths: ["/Users/example"],
            rootGroup: .all([
                .rule(.nameContains("report")),
                .any([.exclude(.pathContains("tmp"))])
            ]),
            requiresContentScan: false,
            excludedPathFragments: ["tmp"]
        )
        let builder = SearchPlanBuilder()

        let plan = builder.build(from: compiledQuery, mode: .standard)

        XCTAssertEqual(plan.rootGroup, .all([.rule(.nameContains("report"))]))
        XCTAssertEqual(plan.excludedPathFragments, ["tmp"])
    }

    func testProvidersExposeConsistentKind() {
        XCTAssertEqual(LocalFilesystemProvider().kind, .local)
        XCTAssertEqual(PrivilegedFilesystemProvider().kind, .privileged)
    }

    func testSpecialFolderPlannerExcludesConfiguredFolderUnlessItIsTheExplicitRoot() {
        let configuration = SpecialFoldersConfiguration(
            rules: [SpecialFolderRule(path: "/Users/example/Library", disposition: .exclude)]
        )
        let planner = SpecialFolderPlanner()

        let broadPlan = planner.plan(rootPath: "/Users/example", configuration: configuration)
        let targetedPlan = planner.plan(rootPath: "/Users/example/Library", configuration: configuration)

        XCTAssertEqual(broadPlan.specialFolderExclusions, ["/Users/example/Library"])
        XCTAssertTrue(targetedPlan.specialFolderExclusions.isEmpty)
    }

    func testSpecialFolderPlannerKeepsIncludedDescendantsAndStoresSlowSearchPaths() {
        let configuration = SpecialFoldersConfiguration(
            rules: [
                SpecialFolderRule(path: "/Users/example/Library", disposition: .exclude),
                SpecialFolderRule(path: "/Users/example/Library/Mail", disposition: .include),
                SpecialFolderRule(path: "/Users/example/Downloads", disposition: .slowSearch)
            ]
        )
        let planner = SpecialFolderPlanner()

        let plan = planner.plan(rootPath: "/Users/example", configuration: configuration)

        XCTAssertEqual(plan.includedPathRoots, ["/Users/example/Library/Mail"])
        XCTAssertEqual(plan.specialFolderExclusions, ["/Users/example/Library"])
        XCTAssertEqual(plan.slowSearchPaths, ["/Users/example/Downloads"])
        XCTAssertTrue(plan.allows(path: "/Users/example/Library"))
        XCTAssertTrue(plan.allows(path: "/Users/example/Library/Mail"))
        XCTAssertFalse(plan.allows(path: "/Users/example/Library/Caches"))
    }
}
