import Darwin
import XCTest
@testable import FileHound

final class DirectoryWalkerTests: XCTestCase {
    func testWalkSkipsDotPrefixedAndFlaggedHiddenItemsWhenExcludingHiddenFiles() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file(".secret.txt", contents: "hidden")
            try builder.file(".dir/inside.txt", contents: "hidden")
            try builder.file("Library/inside.txt", contents: "hidden by flag")
            try builder.file("visible.txt", contents: "shown")
        }
        // 与 ~/Library 一样只带 UF_HIDDEN 标志、名称不以 “.” 开头的目录也不可见
        XCTAssertEqual(chflags(fixture.path + "/Library", UInt32(UF_HIDDEN)), 0)

        let items = DirectoryWalker().walk(plan: SearchPlan(rootPaths: [fixture.path]), includeHiddenFiles: false)

        XCTAssertEqual(items.map(\.path), [fixture.path + "/visible.txt"])
    }

    func testWalkIncludesHiddenFilesWhenRequested() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file(".secret.txt", contents: "hidden")
            try builder.file("Library/inside.txt", contents: "hidden by flag")
            try builder.file("visible.txt", contents: "shown")
        }
        XCTAssertEqual(chflags(fixture.path + "/Library", UInt32(UF_HIDDEN)), 0)

        let items = DirectoryWalker().walk(plan: SearchPlan(rootPaths: [fixture.path]), includeHiddenFiles: true)

        XCTAssertEqual(
            Set(items.map(\.path)),
            Set([".secret.txt", "Library", "Library/inside.txt", "visible.txt"].map { fixture.path + "/" + $0 })
        )
        XCTAssertEqual(items.first { $0.lastPathComponent == "Library" }?.isHidden, true)
    }

    func testWalkContinuesWhenSubdirectoryCannotBeRead() {
        let walker = DirectoryWalker(provider: FailingSubdirectoryProvider())

        let items = walker.walk(plan: SearchPlan(rootPaths: ["/root"]), includeHiddenFiles: true)

        XCTAssertTrue(items.map(\.path).contains("/root/visible.txt"))
        XCTAssertTrue(items.map(\.path).contains("/root/blocked"))
    }

    func testBulkListerReportsNamesTypesAndHiddenFlagsWithoutFollowingSymlinks() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("文档/报告.txt", contents: "a")
            try builder.file("plain.dmgcanvas", contents: "b")
            try builder.file("Flagged/c.txt", contents: "c")
        }
        try FileManager.default.createSymbolicLink(
            atPath: fixture.rootURL.appendingPathComponent("link").path,
            withDestinationPath: fixture.rootURL.appendingPathComponent("文档").path
        )
        XCTAssertEqual(chflags(fixture.path + "/Flagged", UInt32(UF_HIDDEN)), 0)

        let items = try BulkDirectoryLister.list(atPath: fixture.path)

        XCTAssertEqual(
            Set(items),
            [
                DirectoryListingItem(name: "文档", isDirectory: true),
                DirectoryListingItem(name: "plain.dmgcanvas", isDirectory: false),
                DirectoryListingItem(name: "link", isDirectory: false),
                DirectoryListingItem(name: "Flagged", isDirectory: true, hasHiddenFlag: true)
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

        let paths = DirectoryWalker(concurrency: 8).walk(plan: SearchPlan(rootPaths: [fixture.path]), includeHiddenFiles: true).map(\.path)

        XCTAssertEqual(paths.count, expected.count)
        XCTAssertEqual(Set(paths), expected)
    }

    func testWalkStopsWhenVisitorRequestsStop() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            for index in 0..<50 {
                try builder.file("d\(index)/f.txt", contents: "")
            }
        }

        let completed = DirectoryWalker().walk(plan: SearchPlan(rootPaths: [fixture.path]), includeHiddenFiles: true) { _ in .stop }

        XCTAssertFalse(completed)
    }

    func testCancelledTokenStopsTheWalk() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("a/b.txt", contents: "")
        }
        let token = SearchCancellationToken()
        token.cancel()
        let visited = LockedStrings()

        let completed = DirectoryWalker().walk(
            plan: SearchPlan(rootPaths: [fixture.path]),
            includeHiddenFiles: true,
            cancellation: token
        ) { entry in
            visited.append(entry.path)
            return .continue
        }

        XCTAssertFalse(completed)
        XCTAssertTrue(visited.values.isEmpty)
    }

    func testSlowSearchFoldersAreWalkedAfterEverythingElse() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            for index in 0..<5 {
                try builder.file("Slow/s\(index)/f.txt", contents: "")
                try builder.file("Fast\(index)/a/b/f.txt", contents: "")
            }
        }
        let planning = SpecialFolderPlanner().plan(
            rootPath: fixture.path,
            configuration: SpecialFoldersConfiguration(rules: [
                SpecialFolderRule(path: fixture.path + "/Slow", disposition: .slowSearch)
            ])
        )
        let order = LockedStrings()

        DirectoryWalker(concurrency: 4).walk(
            plan: SearchPlan(rootPaths: [fixture.path], specialFolderPlanning: [planning]),
            includeHiddenFiles: true
        ) { entry in
            order.append(entry.path)
            return .continue
        }

        let visits = order.values
        let slowPrefix = fixture.path + "/Slow/"
        let firstSlowChild = try XCTUnwrap(visits.firstIndex { $0.hasPrefix(slowPrefix) })
        let lastOtherEntry = try XCTUnwrap(visits.lastIndex { $0.hasPrefix(slowPrefix) == false })
        // 慢速文件夹本身作为条目照常回调，但其中的内容要等其他所有目录遍历完才开始
        XCTAssertGreaterThan(firstSlowChild, lastOtherEntry)
        XCTAssertEqual(visits.filter { $0.hasPrefix(slowPrefix) }.count, 10)
        XCTAssertEqual(visits.count, 1 + 10 + 5 * 4)
    }

    func testEachRootUsesItsOwnSpecialFolderPlanning() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("one/Skip/a.txt", contents: "")
            try builder.file("two/Skip/b.txt", contents: "")
        }
        let configuration = SpecialFoldersConfiguration(rules: [
            SpecialFolderRule(path: fixture.path + "/one/Skip", disposition: .exclude)
        ])
        let roots = [fixture.path + "/one", fixture.path + "/two"]
        let planner = SpecialFolderPlanner()

        let paths = DirectoryWalker().walk(
            plan: SearchPlan(rootPaths: roots, specialFolderPlanning: roots.map { planner.plan(rootPath: $0, configuration: configuration) }),
            includeHiddenFiles: true
        ).map(\.path)

        XCTAssertEqual(Set(paths), [fixture.path + "/two/Skip", fixture.path + "/two/Skip/b.txt"])
    }

    func testLocalProviderReadsEmptyAndLargeMappedFiles() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("empty.txt", contents: "")
        }
        let provider = LocalFilesystemProvider()
        XCTAssertEqual(try provider.contentsOfFile(atPath: fixture.path + "/empty.txt").count, 0)

        // 稀疏文件：超过 64MB 时走内存映射，不占用实际磁盘空间
        let largePath = fixture.path + "/large.bin"
        XCTAssertTrue(FileManager.default.createFile(atPath: largePath, contents: nil))
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: largePath))
        let size: UInt64 = (64 << 20) + 4096
        try handle.truncate(atOffset: size)
        try handle.seek(toOffset: size - 6)
        try handle.write(contentsOf: Data("needle".utf8))
        try handle.close()
        defer { try? FileManager.default.removeItem(atPath: largePath) }

        let data = try provider.contentsOfFile(atPath: largePath)
        XCTAssertEqual(UInt64(data.count), size)
        XCTAssertEqual(data.suffix(6), Data("needle".utf8))
        // 区分大小写时只需 memmem，测试不受未优化构建中逐字节循环的拖累
        XCTAssertTrue(try ContentMatcher().matches(
            data: data,
            rule: SearchRuleSelection(field: .textContent, operator: .contains, value: "needle"),
            compareOptions: [],
            caseSensitive: true
        ))
    }
}

private struct FailingSubdirectoryProvider: FilesystemAccessProviding {
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
