import Darwin
import Foundation
import Testing
@testable import FileHound

// MARK: - 测试公共设施

/// 没有任何挂载点的卷目录搜索，保证测试不读取本机真实的挂载表、不调用 searchfs
struct NoVolumeCatalogSearcher: VolumeCatalogSearching {
    func mountPoints() -> [String] {
        []
    }

    func search(
        volumePath: String,
        nameFragment: String,
        shouldStop: () -> Bool,
        onMatches: ([VolumeCatalogMatch]) -> Void
    ) throws {}
}

extension SearchExecutor {
    /// 测试专用：特殊文件夹配置放在内存里，不启用卷目录搜索，Spotlight 默认没有结果，避免依赖本机状态
    static func hermetic(
        walker: DirectoryWalker = DirectoryWalker(),
        provider: any FilesystemAccessProviding = LocalFilesystemProvider(),
        spotlight: SpotlightSearchService = SpotlightSearchService(runQuery: { _, _ in [] }),
        catalogSearcher: any VolumeCatalogSearching = NoVolumeCatalogSearcher(),
        specialFolders: SpecialFoldersConfiguration = .empty,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) -> SearchExecutor {
        let store = SpecialFoldersStore(storage: InMemoryKeyValueStore())
        try? store.save(specialFolders)
        return SearchExecutor(
            walker: walker,
            provider: provider,
            spotlightSearchService: spotlight,
            catalogSearcher: catalogSearcher,
            specialFoldersStore: store,
            nowProvider: nowProvider
        )
    }
}

/// 轮询等待条件成立，超时返回 false；替代固定时长的 sleep
func eventually(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

/// 线程安全地记录字符串（查询、路径等）
final class LockedStrings: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

/// 列目录时什么都返回不了的文件访问：遍历找不到任何条目，属性与内容按真实文件读取
final class EmptyListingProvider: FilesystemAccessProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var listed = false
    private let readsContent: Bool

    init(readsContent: Bool = true) {
        self.readsContent = readsContent
    }

    var didListDirectory: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listed
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        lock.lock()
        listed = true
        lock.unlock()
        return []
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }

    func contentsOfFile(atPath path: String) throws -> Data {
        if readsContent == false {
            Issue.record("不应读取文件内容：\(path)")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
}

private func relativePaths(_ result: SearchExecutionResult, root: String) -> [String] {
    result.items.map { String($0.path.dropFirst(root.count + 1)) }.sorted()
}

// MARK: - Spotlight 查询

struct SpotlightQueryTests {
    private let service = SpotlightSearchService(runQuery: { _, _ in [] })

    @Test
    func extensionRulesMatchFileNameSuffixAndOrGroupsAreParenthesized() {
        #expect(
            service.buildQuery(from: [SearchRuleSelection(field: .extensionName, operator: .isExactly, value: " .dmgcanvas ")])
                == "kMDItemFSName == '*.dmgcanvas'cd"
        )
        #expect(
            service.buildQuery(from: [SearchRuleSelection(field: .extensionName, operator: .isAnyOf, value: "dmg, pkg")])
                == "kMDItemFSName == '*.dmg'cd || kMDItemFSName == '*.pkg'cd"
        )
        #expect(service.buildQuery(from: [SearchRuleSelection(field: .extensionName, operator: .isNot, value: "dmg")]) == nil)

        // && 优先级高于 ||：含 || 的条件必须整体加括号，否则会选中所有 *.pkg
        #expect(
            service.buildQuery(from: [
                SearchRuleSelection(field: .name, operator: .contains, value: "invoice"),
                SearchRuleSelection(field: .extensionName, operator: .isAnyOf, value: "dmg, pkg")
            ]) == "(kMDItemFSName == '*invoice*'cd) && (kMDItemFSName == '*.dmg'cd || kMDItemFSName == '*.pkg'cd)"
        )
        #expect(
            service.buildQuery(from: [
                SearchRuleSelection(field: .textContent, operator: .containsAnyOf, value: "alpha beta"),
                SearchRuleSelection(field: .name, operator: .isAnyOf, value: "a.txt, b.txt")
            ]) == "(kMDItemTextContent == \"*alpha*\"cd || kMDItemTextContent == \"*beta*\"cd) && (kMDItemFSName == 'a.txt'cd || kMDItemFSName == 'b.txt'cd)"
        )
    }

    @Test
    func textContentQueriesOnlyTheContentAttribute() {
        // 不再使用会匹配文件名等元数据的自由文本查询（"32x32"）
        #expect(
            service.buildQuery(from: [SearchRuleSelection(field: .textContent, operator: .contains, value: "32x32")])
                == "kMDItemTextContent == \"*32x32*\"cd"
        )
        #expect(
            service.buildQuery(from: [SearchRuleSelection(field: .textContent, operator: .containsWords, value: "alpha beta")])
                == "kMDItemTextContent == \"*alpha*\"cd && kMDItemTextContent == \"*beta*\"cd"
        )
        // “是任一”要求整个内容相等，Spotlight 无法表达
        #expect(service.buildQuery(from: [SearchRuleSelection(field: .textContent, operator: .isAnyOf, value: "a b")]) == nil)
        // kMDItemPath 不能用于查询
        #expect(service.buildQuery(from: [SearchRuleSelection(field: .path, operator: .contains, value: "Users")]) == nil)
    }

    @Test
    func queryValuesEscapeQuotesBackslashesAndWildcards() {
        #expect(
            service.buildQuery(from: [SearchRuleSelection(field: .name, operator: .contains, value: "O'Neil*")])
                == "kMDItemFSName == '*O\\'Neil\\**'cd"
        )
        #expect(
            service.buildQuery(from: [SearchRuleSelection(field: .textContent, operator: .contains, value: "say \"hi\" \\ *")])
                == "kMDItemTextContent == \"*say \\\"hi\\\" \\\\ \\**\"cd"
        )
    }

    @Test
    func wordCandidateQueryIsOnlyBuiltForPunctuatedOrNonASCIITextContent() throws {
        let queries = LockedStrings()
        let service = SpotlightSearchService { _, query in
            queries.append(query)
            return []
        }

        #expect(try service.searchTextContentCandidates(
            rootPath: "/",
            rules: [SearchRuleSelection(field: .textContent, operator: .contains, value: "05-屏幕截图")]
        ) { _ in })
        #expect(queries.values == ["kMDItemTextContent == \"*05*\"cdw && kMDItemTextContent == \"*屏幕*\"cdw && kMDItemTextContent == \"*截图*\"cdw"])
        #expect(try service.searchTextContentCandidates(
            rootPath: "/",
            rules: [SearchRuleSelection(field: .textContent, operator: .contains, value: "32x32")]
        ) { _ in } == false)
        // 不带标点的中文也会被索引切成多个词
        _ = try service.searchTextContentCandidates(
            rootPath: "/",
            rules: [SearchRuleSelection(field: .textContent, operator: .contains, value: "屏幕截图")]
        ) { _ in }
        #expect(queries.values.last == "kMDItemTextContent == \"*屏幕*\"cdw && kMDItemTextContent == \"*截图*\"cdw")
        #expect(try service.searchTextContentCandidates(
            rootPath: "/",
            rules: [SearchRuleSelection(field: .name, operator: .contains, value: "a-b")]
        ) { _ in } == false)
    }

    @Test
    func processOutputKeepsBatchesWrittenRightBeforeExit() throws {
        // mdfind 先输出一批，过一会儿再输出剩下的并立即退出；最后一批不能丢
        let lines = try SpotlightSearchService.outputLines(
            ofExecutableAt: "/bin/sh",
            arguments: ["-c", "echo first; sleep 0.2; i=0; while [ $i -lt 20000 ]; do echo line$i; i=$((i+1)); done"]
        )
        #expect(lines.count == 20001)
        #expect(lines.first == "first")
        #expect(lines.last == "line19999")
    }

    @Test
    func processOutputStreamsLinesAndStopsOnRequest() throws {
        let received = LockedStrings()
        let started = Date()
        // 第一行之后进程会睡 30 秒；收到第一行就请求停止，应立即结束进程并正常返回
        try SpotlightSearchService.streamOutputLines(
            ofExecutableAt: "/bin/sh",
            arguments: ["-c", "echo first; exec sleep 30"],
            shouldStop: { received.values.isEmpty == false }
        ) { received.append($0) }

        #expect(received.values == ["first"])
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test
    func processOutputTimesOut() {
        #expect(throws: SpotlightSearchError.self) {
            try SpotlightSearchService.streamOutputLines(
                ofExecutableAt: "/bin/sh",
                arguments: ["-c", "exec sleep 30"],
                timeout: 0.2
            ) { _ in }
        }
    }
}

// MARK: - 执行流程

struct SearchExecutorTests {
    @Test
    func streamingProgressEventuallyReportsResultsThrottledAfterLastEmission() async throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            for index in 0..<5 {
                try builder.file("folder/report-\(index).txt", contents: "")
            }
        }
        let recorder = LockedStrings()

        let result = SearchExecutor.hermetic().executeStreaming(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        ) { progress in
            recorder.append(String(progress.matchedCount))
        }

        #expect(result.items.count == 5)
        // 节流间隔内的结果应在间隔结束后补发，而不是一直等到下一条命中
        #expect(await eventually { recorder.values.last == "5" })
    }

    @Test
    func executeFindsExtensionMatchesAcrossNestedFolders() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("a/b/c/Installer.dmgcanvas", contents: "")
            try builder.file("a/Other.DMGCANVAS", contents: "")
            try builder.file("a/b/notes.txt", contents: "")
            try builder.file("x/dmgcanvas", contents: "")
        }

        let result = SearchExecutor.hermetic().execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .extensionName, operator: .isExactly, value: ".dmgcanvas")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(relativePaths(result, root: fixture.path) == ["a/Other.DMGCANVAS", "a/b/c/Installer.dmgcanvas"])
    }

    @Test
    func executeSkipsEntriesThatCannotBeRead() {
        let provider = FailingSearchProvider()
        let executor = SearchExecutor.hermetic(walker: DirectoryWalker(provider: provider), provider: provider)

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: "/root",
                rules: [SearchRuleSelection(field: .textContent, operator: .contains, value: "report")]
            )
        )

        #expect(result.items.map(\.path) == ["/root/report.txt"])
    }

    @Test
    func executeUsesSpotlightForSupportedNameRules() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "hello")
        }
        let expectedPath = fixture.path + "/report.txt"
        let queries = LockedStrings()
        // 遍历什么也找不到，结果只能来自 Spotlight
        let listing = EmptyListingProvider()
        let executor = SearchExecutor.hermetic(
            walker: DirectoryWalker(provider: listing),
            provider: listing,
            spotlight: SpotlightSearchService { rootPath, query in
                queries.append(rootPath + " " + query)
                return [expectedPath]
            }
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
            )
        )

        #expect(result.items.map(\.path) == [expectedPath])
        #expect(queries.values == [fixture.path + " kMDItemFSName == '*report*'cd"])
        #expect(listing.didListDirectory)
    }

    @Test
    func executeMergesSpotlightAndWalkerResultsWhenEnabled() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "hello")
            try builder.file("spotlight-report.txt", contents: "hello")
        }
        let spotlightPath = fixture.path + "/spotlight-report.txt"
        let executor = SearchExecutor.hermetic(spotlight: SpotlightSearchService(runQuery: { _, _ in [spotlightPath] }))

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: true)
        )

        // 两条路径都找到 spotlight-report.txt，只保留一份
        #expect(relativePaths(result, root: fixture.path) == ["report.txt", "spotlight-report.txt"])
    }

    @Test
    func executeSkipsSpotlightWhenPreferenceDisablesIt() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "hello")
        }
        let executor = SearchExecutor.hermetic(spotlight: SpotlightSearchService(runQuery: { _, _ in
            Issue.record("Spotlight should not be queried when disabled")
            return []
        }))

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(result.items.map(\.path) == [fixture.path + "/report.txt"])
    }

    /// 模拟一直没有结束的 mdfind：只有 shouldStop 返回 true 才结束，最多等 10 秒
    private func endlessSpotlight(recordingStopsIn stops: LockedStrings, onStart: @escaping @Sendable () -> Void = {}) -> SpotlightSearchService {
        SpotlightSearchService(streamingQuery: { _, _, shouldStop, _ in
            onStart()
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if shouldStop() {
                    stops.append("stopped")
                    return
                }
                usleep(5_000)
            }
        })
    }

    @Test
    func spotlightIsStoppedWhenTheLimitIsReached() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "hello")
        }
        let stops = LockedStrings()
        let started = Date()

        let result = SearchExecutor.hermetic(spotlight: endlessSpotlight(recordingStopsIn: stops)).execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [
                    SearchRuleSelection(field: .name, operator: .contains, value: "report"),
                    SearchRuleSelection(field: .limitAmount, operator: .isExactly, value: "1")
                ]
            )
        )

        #expect(result.items.count == 1)
        #expect(stops.values == ["stopped"])
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test
    func cancellationStopsARunningSpotlightQuery() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "hello")
        }
        let stops = LockedStrings()
        let token = SearchCancellationToken()
        let started = Date()
        // 查询开始后由“用户”取消搜索
        let spotlight = endlessSpotlight(recordingStopsIn: stops, onStart: { token.cancel() })

        _ = SearchExecutor.hermetic(spotlight: spotlight).execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
            ),
            cancellation: token
        )

        #expect(stops.values == ["stopped"])
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test
    func executeAnnotatesNormalizedNameAndExtensionMatchesForHighlighting() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.lookin", contents: "hello")
        }
        let executor = SearchExecutor.hermetic(spotlight: SpotlightSearchService(runQuery: { _, _ in
            throw SpotlightSearchError.queryFailed(status: 1)
        }))

        let nameResult = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [
                    SearchRuleSelection(field: .invisibleItems, operator: .isExactly, value: "true"),
                    SearchRuleSelection(field: .name, operator: .contains, value: " report ")
                ]
            )
        )
        let extensionResult = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .extensionName, operator: .contains, value: " .lookin ")]
            )
        )

        #expect(nameResult.items.first?.highlightKind == .name)
        #expect(nameResult.items.first?.highlightQuery == "report")
        // 预览取第一条普通条件的值，开关类条件不参与
        #expect(nameResult.items.first?.previewSnippet == "report")
        #expect(extensionResult.items.first?.highlightKind == .extensionName)
        #expect(extensionResult.items.first?.highlightQuery == "lookin")
    }

    @Test
    func executeSkipsResultsInsideExcludedSpecialFolders() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("visible/report.txt", contents: "hello")
            try builder.file("Library/hidden.txt", contents: "hello")
        }
        let executor = SearchExecutor.hermetic(
            specialFolders: SpecialFoldersConfiguration(
                rules: [SpecialFolderRule(path: fixture.path + "/Library", disposition: .exclude)]
            )
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .containsAnyOf, value: "report hidden")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(relativePaths(result, root: fixture.path) == ["visible/report.txt"])
    }

    @Test
    func eachRootKeepsItsOwnSpecialFolderPlanning() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("Library/inside.txt", contents: "a")
            try builder.file("Documents/outside.txt", contents: "b")
        }
        // Library 被排除，但它本身也是一个搜索根：排除规则只作用于外层根，不能串到 Library 这个根上
        let executor = SearchExecutor.hermetic(
            specialFolders: SpecialFoldersConfiguration(
                rules: [SpecialFolderRule(path: fixture.path + "/Library", disposition: .exclude)]
            )
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Roots",
                rootPaths: [fixture.path, fixture.path + "/Library"],
                rules: [SearchRuleSelection(field: .extensionName, operator: .isExactly, value: "txt")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(relativePaths(result, root: fixture.path) == ["Documents/outside.txt", "Library/inside.txt"])
    }

    @Test
    func nestedRootsAreWalkedOnlyOnce() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("sub/deep/a.txt", contents: "a")
        }
        let recorder = ListingRecordingProvider()
        let executor = SearchExecutor.hermetic(walker: DirectoryWalker(provider: recorder))

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Roots",
                rootPaths: [fixture.path, fixture.path + "/sub", fixture.path + "/"],
                rules: [SearchRuleSelection(field: .name, operator: .isExactly, value: "a.txt")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(relativePaths(result, root: fixture.path) == ["sub/deep/a.txt"])
        #expect(recorder.listedPaths.filter { $0.hasSuffix("/deep") }.count == 1)
        #expect(recorder.listedPaths.filter { $0.hasSuffix("/sub") }.count == 1)
    }

    @Test
    func packageContentsAreJudgedRelativeToTheSearchRoot() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("Xcode.app/Contents/Info.plist", contents: "a")
            try builder.file("Other/Info.plist", contents: "b")
        }
        let executor = SearchExecutor.hermetic()
        let rules = [
            SearchRuleSelection(field: .name, operator: .isExactly, value: "Info.plist"),
            SearchRuleSelection(field: .packageContents, operator: .isExactly, value: "false")
        ]

        let fromOutside = executor.execute(
            request: SearchRequest(scopeDescription: "Root", rootPath: fixture.path, rules: rules),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )
        // 搜索根本身在包内时，其中的条目不因“不含包内容”被过滤
        let fromInsidePackage = executor.execute(
            request: SearchRequest(scopeDescription: "Root", rootPath: fixture.path + "/Xcode.app", rules: rules),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(relativePaths(fromOutside, root: fixture.path) == ["Other/Info.plist"])
        #expect(fromInsidePackage.items.map(\.path) == [fixture.path + "/Xcode.app/Contents/Info.plist"])
    }

    @Test
    func limitAmountStopsAtTheLimitAcrossThreadsAndLessThanOneMeansNoResults() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            for folder in 0..<20 {
                for file in 0..<10 {
                    try builder.file("d\(folder)/f\(file).txt", contents: "")
                }
            }
        }
        let executor = SearchExecutor.hermetic(walker: DirectoryWalker(concurrency: 8))
        let txt = SearchRuleSelection(field: .extensionName, operator: .isExactly, value: "txt")

        let limited = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [txt, SearchRuleSelection(field: .limitAmount, operator: .isExactly, value: "5")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )
        let none = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [txt, SearchRuleSelection(field: .limitAmount, operator: .isLessThan, value: "1")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(limited.items.count == 5)
        #expect(Set(limited.items.map(\.path)).count == 5)
        #expect(none.items.isEmpty)
    }

    @Test
    func cancellationStopsAnEndlessWalk() {
        let token = SearchCancellationToken()
        // 每个目录都有子目录的无限目录树，只有取消才能结束
        let provider = EndlessTreeProvider { listedCount in
            if listedCount >= 50 {
                token.cancel()
            }
        }
        let executor = SearchExecutor.hermetic(walker: DirectoryWalker(provider: provider), provider: provider)

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: "/endless",
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "never-matches")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false),
            cancellation: token
        )

        #expect(result.items.isEmpty)
        #expect(provider.listedCount < 50 + 20)
    }

    @Test
    func cancelledTokenSkipsTheSearch() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "")
        }
        let token = SearchCancellationToken()
        token.cancel()

        let result = SearchExecutor.hermetic().execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
            ),
            cancellation: token
        )

        #expect(result.items.isEmpty)
    }

    @Test
    func invalidRegexMatchesNothingEvenWhenNegated() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("a.txt", contents: "")
        }
        let executor = SearchExecutor.hermetic()

        for searchOperator in [SearchRuleOperator.matchesRegex, .doesNotMatchRegex] {
            let result = executor.execute(
                request: SearchRequest(
                    scopeDescription: "Root",
                    rootPath: fixture.path,
                    rules: [SearchRuleSelection(field: .name, operator: searchOperator, value: "(")]
                ),
                options: SearchExecutionOptions(includeSpotlightResults: false)
            )
            #expect(result.items.isEmpty)
        }
    }

    @Test
    func hiddenAncestorsOfSpotlightResultsAreSkippedWhenInvisibleItemsAreExcluded() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file(".dot/report.txt", contents: "")
            try builder.file("Flagged/report.txt", contents: "")
            try builder.file("Visible/report.txt", contents: "")
        }
        #expect(chflags(fixture.path + "/Flagged", UInt32(UF_HIDDEN)) == 0)
        let paths = ["/.dot/report.txt", "/Flagged/report.txt", "/Visible/report.txt"].map { fixture.path + $0 }
        let listing = EmptyListingProvider()
        let executor = SearchExecutor.hermetic(
            walker: DirectoryWalker(provider: listing),
            provider: listing,
            spotlight: SpotlightSearchService(runQuery: { _, _ in paths })
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [
                    SearchRuleSelection(field: .name, operator: .contains, value: "report"),
                    SearchRuleSelection(field: .invisibleItems, operator: .isExactly, value: "false")
                ]
            )
        )

        #expect(relativePaths(result, root: fixture.path) == ["Visible/report.txt"])
    }

    // MARK: 文本内容与 Spotlight

    @Test
    func trustedSpotlightTextContentHitsAreNotReReadButTheWalkStillRuns() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("icons/manifest.pdf", contents: "%PDF binary")
        }
        let expectedPath = fixture.path + "/icons/manifest.pdf"
        // 不读取内容（PDF 等格式按字节判定不了），列目录也找不到任何条目
        let provider = EmptyListingProvider(readsContent: false)
        let queries = LockedStrings()
        let executor = SearchExecutor.hermetic(
            walker: DirectoryWalker(provider: provider),
            provider: provider,
            spotlight: SpotlightSearchService { rootPath, query in
                queries.append(query)
                return [expectedPath]
            }
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .textContent, operator: .contains, value: "32x32")]
            )
        )

        #expect(result.items.map(\.path) == [expectedPath])
        #expect(queries.values == ["kMDItemTextContent == \"*32x32*\"cd"])
        // Spotlight 有结果也继续遍历：它不覆盖未索引的位置
        #expect(provider.didListDirectory)
    }

    @Test
    func textContentSearchFindsFilesSpotlightMissed() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("indexed/a.txt", contents: "the needle is here")
            try builder.file("unindexed/b.txt", contents: "another needle")
            try builder.file("unindexed/c.txt", contents: "nothing")
        }
        let executor = SearchExecutor.hermetic(
            spotlight: SpotlightSearchService(runQuery: { _, _ in [fixture.path + "/indexed/a.txt"] })
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .textContent, operator: .contains, value: "needle")]
            )
        )

        #expect(relativePaths(result, root: fixture.path) == ["indexed/a.txt", "unindexed/b.txt"])
    }

    @Test
    func spotlightTextContentHitsExcludeFoldersAndAreRecheckedWhenCaseSensitive() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("Needle Folder/readme.txt", contents: "nothing here")
            try builder.file("upper.txt", contents: "NEEDLE")
        }
        let listing = EmptyListingProvider()
        let hits = [fixture.path + "/Needle Folder", fixture.path + "/upper.txt"]
        let executor = SearchExecutor.hermetic(
            walker: DirectoryWalker(provider: listing),
            provider: listing,
            spotlight: SpotlightSearchService(runQuery: { _, _ in hits })
        )

        let insensitive = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .textContent, operator: .contains, value: "needle")]
            )
        )
        // 区分大小写时 Spotlight（不区分大小写）的命中只是候选，需要读取文件复核
        let sensitive = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [
                    SearchRuleSelection(field: .textContent, operator: .contains, value: "needle"),
                    SearchRuleSelection(field: .caseSensitive, operator: .isExactly, value: "true")
                ]
            )
        )

        #expect(insensitive.items.map(\.path) == [fixture.path + "/upper.txt"])
        #expect(sensitive.items.isEmpty)
    }

    @Test
    func punctuatedTextContentSearchVerifiesSpotlightWordCandidates() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("lib/UIImage+WJ.m", contents: "//  05-屏幕截图\n")
            try builder.file("lib/notes.txt", contents: "05 张屏幕截图")
        }
        let matchingPath = fixture.path + "/lib/UIImage+WJ.m"
        let candidatePath = fixture.path + "/lib/notes.txt"
        let listing = EmptyListingProvider()
        let executor = SearchExecutor.hermetic(
            walker: DirectoryWalker(provider: listing),
            provider: listing,
            spotlight: SpotlightSearchService { _, query in
                // 子串查询查不到，按词查询返回两个候选
                query == "kMDItemTextContent == \"*05*\"cdw && kMDItemTextContent == \"*屏幕*\"cdw && kMDItemTextContent == \"*截图*\"cdw"
                    ? [matchingPath, candidatePath]
                    : []
            }
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .textContent, operator: .contains, value: "05-屏幕截图")]
            )
        )

        #expect(result.items.map(\.path) == [matchingPath])
    }

    // MARK: 日期、类型

    @Test
    func executeSupportsFafDateOperatorsAndKindMatching() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("Preview.app/Contents/Info.plist", contents: "plist")
            try builder.file("today.txt", contents: "hello")
            try builder.file("older.txt", contents: "older")
        }

        let fileManager = FileManager.default
        let bundlePath = fixture.path + "/Preview.app"
        let todayPath = fixture.path + "/today.txt"
        let olderPath = fixture.path + "/older.txt"
        let staleDate = try #require(ISO8601DateFormatter().date(from: "2026-04-08T08:00:00Z"))
        try fileManager.setAttributes([.modificationDate: try #require(ISO8601DateFormatter().date(from: "2026-04-12T08:00:00Z"))], ofItemAtPath: todayPath)
        for path in [olderPath, bundlePath, bundlePath + "/Contents", bundlePath + "/Contents/Info.plist"] {
            try fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: path)
        }

        let executor = SearchExecutor.hermetic(nowProvider: { ISO8601DateFormatter().date(from: "2026-04-12T10:00:00Z")! })

        let kindResult = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .kind, operator: .isExactly, value: "kind.application")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )
        let dateResult = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .lastModifiedDate, operator: .isWithinTheLast, value: "2|day")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(kindResult.items.map(\.path) == [bundlePath])
        #expect(dateResult.items.map(\.path) == [todayPath])
    }

    @Test
    func dateBoundariesUseNextMidnightAndTheInjectedClock() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("last-moment.txt", contents: "")
            try builder.file("next-day.txt", contents: "")
            try builder.file("yesterday.txt", contents: "")
        }
        let calendar = Calendar(identifier: .gregorian)
        func localDate(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int, nanosecond: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: 2026, month: 4, day: day, hour: hour, minute: minute, second: second, nanosecond: nanosecond
            )))
        }
        let fileManager = FileManager.default
        try fileManager.setAttributes([.modificationDate: try localDate(10, 23, 59, 59, nanosecond: 500_000_000)], ofItemAtPath: fixture.path + "/last-moment.txt")
        try fileManager.setAttributes([.modificationDate: try localDate(11, 0, 0, 0)], ofItemAtPath: fixture.path + "/next-day.txt")
        try fileManager.setAttributes([.modificationDate: try localDate(9, 12, 0, 0)], ofItemAtPath: fixture.path + "/yesterday.txt")
        let now = try localDate(10, 15, 0, 0)
        let executor = SearchExecutor.hermetic(nowProvider: { now })

        func run(_ searchOperator: SearchRuleOperator, _ value: String = "") -> [String] {
            relativePaths(executor.execute(
                request: SearchRequest(
                    scopeDescription: "Root",
                    rootPath: fixture.path,
                    rules: [SearchRuleSelection(field: .lastModifiedDate, operator: searchOperator, value: value)]
                ),
                options: SearchExecutionOptions(includeSpotlightResults: false)
            ), root: fixture.path)
        }

        // 23:59:59.5 仍属于 4 月 10 日，不能算作“晚于 4 月 10 日”
        #expect(run(.isAfter, "2026-04-10") == ["next-day.txt"])
        #expect(run(.isOnOrBefore, "2026-04-10") == ["last-moment.txt", "yesterday.txt"])
        #expect(run(.isExactly, "2026-04-10") == ["last-moment.txt"])
        #expect(run(.isBefore, "2026-04-10") == ["yesterday.txt"])
        // “今天”“昨天”以注入的时钟为准，而不是真实的当前日期
        #expect(run(.isToday) == ["last-moment.txt"])
        #expect(run(.isYesterday) == ["yesterday.txt"])
    }

    @Test
    func audioIsNotClassifiedAsVideo() {
        let resolver = FileKindResolver()
        let attributes: [FileAttributeKey: Any] = [.type: FileAttributeType.typeRegular]

        let audio = resolver.kindIDs(for: "/nonexistent/song.mp3", isDirectory: false, attributes: attributes)
        let movie = resolver.kindIDs(for: "/nonexistent/clip.mov", isDirectory: false, attributes: attributes)

        #expect(audio.contains("kind.audio"))
        #expect(audio.contains("kind.video") == false)
        #expect(movie.contains("kind.video"))
        #expect(movie.contains("kind.audio") == false)
    }
}

private struct FailingSearchProvider: FilesystemAccessProviding {
    func contentsOfDirectory(atPath path: String) throws -> [String] {
        switch path {
        case "/root":
            return ["report.txt", "broken.txt"]
        default:
            return []
        }
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        [.type: FileAttributeType.typeRegular, .size: NSNumber(value: 6)]
    }

    func contentsOfFile(atPath path: String) throws -> Data {
        switch path {
        case "/root/report.txt":
            return Data("report".utf8)
        case "/root/broken.txt":
            throw CocoaError(.fileReadNoPermission)
        default:
            return Data()
        }
    }
}

/// 记录列过哪些目录，其余按真实文件系统处理
final class ListingRecordingProvider: FilesystemAccessProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    var listedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        lock.lock()
        paths.append(path)
        lock.unlock()
        return try FileManager.default.contentsOfDirectory(atPath: path)
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }

    func contentsOfFile(atPath path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }
}

/// 无限深的虚拟目录树：每个目录下都有 4 个子目录
private final class EndlessTreeProvider: FilesystemAccessProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let onList: (Int) -> Void

    init(onList: @escaping (Int) -> Void) {
        self.onList = onList
    }

    var listedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        lock.lock()
        count += 1
        let current = count
        lock.unlock()
        onList(current)
        return ["a", "b", "c", "d"]
    }

    func listDirectory(atPath path: String) throws -> [DirectoryListingItem] {
        try contentsOfDirectory(atPath: path).map { DirectoryListingItem(name: $0, isDirectory: true) }
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        [.type: FileAttributeType.typeDirectory]
    }

    func contentsOfFile(atPath path: String) throws -> Data {
        Data()
    }
}

// MARK: - 卷目录搜索

struct SearchExecutorCatalogSearchTests {
    @Test
    func nameFragmentUsesLongestRequiredSubstringThatVolumeSearchCanMatch() {
        func fragment(_ rules: [SearchRuleSelection], diacriticsSensitive: Bool = false) -> String? {
            SearchExecutor.catalogNameFragment(for: rules, diacriticsSensitive: diacriticsSensitive)
        }

        // 区分变音符号时 searchfs 的匹配与规则一致，字母可以放进片段
        #expect(fragment([SearchRuleSelection(field: .extensionName, operator: .isExactly, value: "dmgcanvas")], diacriticsSensitive: true) == ".dmgcanvas")
        #expect(fragment([
            SearchRuleSelection(field: .name, operator: .contains, value: "report"),
            SearchRuleSelection(field: .extensionName, operator: .isExactly, value: "pdf")
        ], diacriticsSensitive: true) == "report")
        #expect(fragment([SearchRuleSelection(field: .name, operator: .containsWords, value: "annual, budget2026")], diacriticsSensitive: true) == "budget2026")
        #expect(fragment([SearchRuleSelection(field: .name, operator: .matchesPattern, value: "Screenshot*.png")], diacriticsSensitive: true) == "Screenshot")
        #expect(fragment([SearchRuleSelection(field: .name, operator: .contains, value: "Ölbild")], diacriticsSensitive: true) == "Ölbild")
        // 大小写映射会改变长度的字符两边折叠规则不一致，需要切开
        #expect(fragment([SearchRuleSelection(field: .name, operator: .contains, value: "Straße")], diacriticsSensitive: true) == "Stra")

        // 忽略变音符号时，名称里的任何字母都可能带变音（searchfs 会因此漏掉），只用数字、标点、汉字组成的片段
        #expect(fragment([SearchRuleSelection(field: .name, operator: .contains, value: "Ölbild")]) == nil)
        #expect(fragment([SearchRuleSelection(field: .name, operator: .contains, value: "report")]) == nil)
        #expect(fragment([SearchRuleSelection(field: .extensionName, operator: .isExactly, value: "dmgcanvas")]) == nil)
        #expect(fragment([SearchRuleSelection(field: .name, operator: .contains, value: "IMG_2026-10")]) == "_2026-10")
        #expect(fragment([SearchRuleSelection(field: .name, operator: .contains, value: "测试报告")]) == "测试报告")
        #expect(fragment([SearchRuleSelection(field: .name, operator: .contains, value: "がき")]) == nil)

        #expect(fragment([SearchRuleSelection(field: .name, operator: .contains, value: "a")], diacriticsSensitive: true) == nil)
        #expect(fragment([SearchRuleSelection(field: .name, operator: .doesNotContain, value: "report")], diacriticsSensitive: true) == nil)
        #expect(fragment([SearchRuleSelection(field: .extensionName, operator: .isAnyOf, value: "dmg, pkg")], diacriticsSensitive: true) == nil)
    }

    @Test
    func diacriticInsensitiveLetterSearchesWalkInsteadOfUsingSearchfs() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("café.txt", contents: "")
            try builder.file("Résumé_x.txt", contents: "")
        }
        let root = fixture.path
        // 假的 searchfs 与真实内核一样区分变音符号：什么都找不到
        let searcher = FakeVolumeCatalogSearcher(mountPoints: [root]) { _ in [] }
        let executor = SearchExecutor.hermetic(catalogSearcher: searcher)

        func run(_ value: String) -> [String] {
            relativePaths(executor.execute(
                request: SearchRequest(
                    scopeDescription: "Root",
                    rootPath: root,
                    rules: [SearchRuleSelection(field: .name, operator: .contains, value: value)]
                ),
                options: SearchExecutionOptions(includeSpotlightResults: false)
            ), root: root)
        }

        #expect(run("cafe") == ["café.txt"])
        #expect(run("Resume") == ["Résumé_x.txt"])
        #expect(searcher.searchedVolumes.isEmpty)
    }

    @Test
    func catalogSearchReplacesWalkAndRechecksEveryCandidate() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("a/Installer.dmgcanvas", contents: "")
            try builder.file("a/Installer.dmgcanvas.zip", contents: "")
            try builder.file(".hidden/Secret.dmgcanvas", contents: "")
            try builder.file("Flagged/Hidden.dmgcanvas", contents: "")
            try builder.file("excluded/Skipped.dmgcanvas", contents: "")
            try builder.file("unlisted/Walked.dmgcanvas", contents: "")
        }
        let root = fixture.path
        #expect(chflags(root + "/Flagged", UInt32(UF_HIDDEN)) == 0)
        let searcher = FakeVolumeCatalogSearcher(mountPoints: [root + "/"]) { volumePath in
            guard volumePath == root else {
                return []
            }
            return [
                VolumeCatalogMatch(path: root + "/a/Installer.dmgcanvas", isDirectory: false),
                VolumeCatalogMatch(path: root + "/a/Installer.dmgcanvas", isDirectory: false),
                VolumeCatalogMatch(path: root + "/a/Installer.dmgcanvas.zip", isDirectory: false),
                VolumeCatalogMatch(path: root + "/.hidden/Secret.dmgcanvas", isDirectory: false),
                VolumeCatalogMatch(path: root + "/Flagged/Hidden.dmgcanvas", isDirectory: false),
                VolumeCatalogMatch(path: root + "/excluded/Skipped.dmgcanvas", isDirectory: false),
                VolumeCatalogMatch(path: "/elsewhere/Outside.dmgcanvas", isDirectory: false)
            ]
        }
        let executor = SearchExecutor.hermetic(catalogSearcher: searcher)

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPaths: [root],
                excludedPaths: [root + "/excluded"],
                rules: [
                    SearchRuleSelection(field: .extensionName, operator: .isExactly, value: "dmgcanvas"),
                    SearchRuleSelection(field: .invisibleItems, operator: .isExactly, value: "false"),
                    SearchRuleSelection(field: .diacriticsSensitive, operator: .isExactly, value: "true")
                ]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        // 卷目录搜索覆盖了整个卷，不再遍历，所以未被搜索返回的条目不会出现
        #expect(result.items.map(\.path) == [root + "/a/Installer.dmgcanvas"])
        #expect(searcher.searchedVolumes == [root])
        #expect(searcher.fragments == [".dmgcanvas"])
    }

    @Test
    func unsupportedVolumesFallBackToWalkingOnlyThatVolume() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("Top.dmgcanvas", contents: "")
            try builder.file("nested/Inner.dmgcanvas", contents: "")
        }
        let root = fixture.path
        let nested = root + "/nested"
        let searcher = FakeVolumeCatalogSearcher(mountPoints: [root, nested], unsupportedVolumes: [nested]) { volumePath in
            volumePath == root ? [VolumeCatalogMatch(path: root + "/Top.dmgcanvas", isDirectory: false)] : []
        }
        let executor = SearchExecutor.hermetic(catalogSearcher: searcher)

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: root,
                rules: [
                    SearchRuleSelection(field: .extensionName, operator: .isExactly, value: "dmgcanvas"),
                    SearchRuleSelection(field: .diacriticsSensitive, operator: .isExactly, value: "true")
                ]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(Set(result.items.map(\.path)) == [root + "/Top.dmgcanvas", nested + "/Inner.dmgcanvas"])
        #expect(Set(searcher.searchedVolumes) == [root, nested])
    }

    @Test
    func depthLimitedSearchesKeepWalking() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("Top.dmgcanvas", contents: "")
            try builder.file("a/b/Deep.dmgcanvas", contents: "")
        }
        let searcher = FakeVolumeCatalogSearcher(mountPoints: [fixture.path]) { _ in [] }
        let executor = SearchExecutor.hermetic(catalogSearcher: searcher)

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [
                    SearchRuleSelection(field: .extensionName, operator: .isExactly, value: "dmgcanvas"),
                    SearchRuleSelection(field: .limitFolderDepth, operator: .isExactly, value: "1"),
                    SearchRuleSelection(field: .diacriticsSensitive, operator: .isExactly, value: "true")
                ]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(result.items.map(\.path) == [fixture.path + "/Top.dmgcanvas"])
        #expect(searcher.searchedVolumes.isEmpty)
    }

    @Test
    func exclusionsDoNotApplyInsideSearchRootsTheyContain() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("Volumes/External/Found.dmgcanvas", contents: "")
            try builder.file("Volumes/Other/Skipped.dmgcanvas", contents: "")
            try builder.file("Local.dmgcanvas", contents: "")
        }
        let root = fixture.path
        let executor = SearchExecutor.hermetic()

        // 与“所有磁盘”相同的形态：既排除 Volumes，又把其中的卷作为搜索根
        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "All",
                rootPaths: [root, root + "/Volumes/External"],
                excludedPaths: [root + "/Volumes"],
                rules: [SearchRuleSelection(field: .extensionName, operator: .isExactly, value: "dmgcanvas")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(Set(result.items.map(\.path)) == [root + "/Local.dmgcanvas", root + "/Volumes/External/Found.dmgcanvas"])
    }
}

private final class FakeVolumeCatalogSearcher: VolumeCatalogSearching, @unchecked Sendable {
    private let lock = NSLock()
    private let mounts: [String]
    private let unsupportedVolumes: Set<String>
    private let matches: (String) -> [VolumeCatalogMatch]
    private var searched: [(volume: String, fragment: String)] = []

    init(
        mountPoints: [String],
        unsupportedVolumes: Set<String> = [],
        matches: @escaping (String) -> [VolumeCatalogMatch]
    ) {
        mounts = mountPoints
        self.unsupportedVolumes = unsupportedVolumes
        self.matches = matches
    }

    var searchedVolumes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return searched.map(\.volume)
    }

    var fragments: [String] {
        lock.lock()
        defer { lock.unlock() }
        return searched.map(\.fragment)
    }

    func mountPoints() -> [String] {
        mounts
    }

    func search(
        volumePath: String,
        nameFragment: String,
        shouldStop: () -> Bool,
        onMatches: ([VolumeCatalogMatch]) -> Void
    ) throws {
        lock.lock()
        searched.append((volumePath, nameFragment))
        lock.unlock()
        if unsupportedVolumes.contains(volumePath) {
            throw VolumeCatalogSearchError.unsupported(errno: ENOTSUP)
        }
        onMatches(matches(volumePath))
    }
}
