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
