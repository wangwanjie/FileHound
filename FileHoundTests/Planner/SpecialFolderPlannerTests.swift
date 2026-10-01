import XCTest
@testable import FileHound

final class SpecialFolderPlannerTests: XCTestCase {
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
