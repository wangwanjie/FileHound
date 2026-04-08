import XCTest
@testable import FileHound

final class DirectoryWalkerTests: XCTestCase {
    func testWalkSkipsHiddenFilesByDefault() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file(".secret.txt", contents: "hidden")
            try builder.file("visible.txt", contents: "shown")
        }

        let plan = SearchPlan(
            rootPaths: [fixture.path],
            rootGroup: .rule(.nameContains("txt")),
            excludedPathFragments: [],
            providerKind: .local,
            shouldScanContents: false
        )

        let items = try DirectoryWalker().walk(plan: plan, includeHiddenFiles: false)

        XCTAssertEqual(items.map(\.lastPathComponent), ["visible.txt"])
    }

    func testWalkIncludesHiddenFilesWhenRequested() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file(".secret.txt", contents: "hidden")
            try builder.file("visible.txt", contents: "shown")
        }

        let plan = SearchPlan(
            rootPaths: [fixture.path],
            rootGroup: .rule(.nameContains("txt")),
            excludedPathFragments: [],
            providerKind: .local,
            shouldScanContents: false
        )

        let items = try DirectoryWalker().walk(plan: plan, includeHiddenFiles: true)

        XCTAssertEqual(items.map(\.lastPathComponent).sorted(), [".secret.txt", "visible.txt"])
    }
}
