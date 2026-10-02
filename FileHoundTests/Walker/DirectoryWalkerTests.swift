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

    func testWalkContinuesWhenSubdirectoryCannotBeRead() throws {
        let provider = FailingSubdirectoryProvider()
        let walker = DirectoryWalker(providerFactory: { _ in provider })
        let plan = SearchPlan(
            rootPaths: ["/root"],
            rootGroup: .rule(.nameContains("txt")),
            excludedPathFragments: [],
            providerKind: .local,
            shouldScanContents: false
        )

        let items = try walker.walk(plan: plan, includeHiddenFiles: true)

        XCTAssertTrue(items.map(\.path).contains("/root/visible.txt"))
        XCTAssertTrue(items.map(\.path).contains("/root/blocked"))
    }

    func testBulkListerReportsNamesAndDirectoryTypesWithoutFollowingSymlinks() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("文档/报告.txt", contents: "a")
            try builder.file("plain.dmgcanvas", contents: "b")
        }
        try FileManager.default.createSymbolicLink(
            atPath: fixture.rootURL.appendingPathComponent("link").path,
            withDestinationPath: fixture.rootURL.appendingPathComponent("文档").path
        )

        let items = try BulkDirectoryLister.list(atPath: fixture.path)

        XCTAssertEqual(
            Set(items),
            [
                DirectoryListingItem(name: "文档", isDirectory: true),
                DirectoryListingItem(name: "plain.dmgcanvas", isDirectory: false),
                DirectoryListingItem(name: "link", isDirectory: false)
            ]
        )
    }

    func testBulkListerThrowsForMissingDirectory() {
        XCTAssertThrowsError(try BulkDirectoryLister.list(atPath: "/nonexistent-\(UUID().uuidString)"))
    }

    func testParallelWalkVisitsEveryEntryExactlyOnce() throws {
        var expected: Set<String> = []
        let fixture = try TemporaryFixtureTree.make { builder in
            for folder in 0..<20 {
                for file in 0..<10 {
                    try builder.file("d\(folder)/s\(file % 3)/f\(file).txt", contents: "")
                }
            }
        }
        for folder in 0..<20 {
            expected.insert(fixture.path + "/d\(folder)")
            for file in 0..<10 {
                expected.insert(fixture.path + "/d\(folder)/s\(file % 3)")
                expected.insert(fixture.path + "/d\(folder)/s\(file % 3)/f\(file).txt")
            }
        }
        let plan = SearchPlan(
            rootPaths: [fixture.path],
            rootGroup: .all([]),
            excludedPathFragments: [],
            providerKind: .local,
            shouldScanContents: false
        )

        let paths = try DirectoryWalker(concurrency: 8).walk(plan: plan, includeHiddenFiles: true).map(\.path)

        XCTAssertEqual(paths.count, expected.count)
        XCTAssertEqual(Set(paths), expected)
    }

    func testWalkStopsWhenVisitorRequestsStop() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            for index in 0..<50 {
                try builder.file("d\(index)/f.txt", contents: "")
            }
        }
        let plan = SearchPlan(
            rootPaths: [fixture.path],
            rootGroup: .all([]),
            excludedPathFragments: [],
            providerKind: .local,
            shouldScanContents: false
        )

        let completed = try DirectoryWalker().walk(plan: plan, includeHiddenFiles: true) { _ in .stop }

        XCTAssertFalse(completed)
    }
}

private struct FailingSubdirectoryProvider: FilesystemAccessProviding {
    let kind: ProviderKind = .local

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        switch path {
        case "/root":
            return ["visible.txt", "blocked"]
        case "/root/blocked":
            throw CocoaError(.fileReadNoPermission)
        default:
            return []
        }
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        switch path {
        case "/root/visible.txt":
            return [.type: FileAttributeType.typeRegular]
        case "/root/blocked":
            return [.type: FileAttributeType.typeDirectory]
        default:
            return [.type: FileAttributeType.typeRegular]
        }
    }

    func contentsOfFile(atPath path: String) throws -> Data {
        Data()
    }
}
