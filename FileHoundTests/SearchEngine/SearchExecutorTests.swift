import Foundation
import Testing
@testable import FileHound

struct SearchExecutorTests {
    @Test
    func executeSkipsEntriesThatCannotBeRead() {
        let provider = FailingSearchProvider()
        let walker = DirectoryWalker(providerFactory: { _ in provider })
        let executor = SearchExecutor(walker: walker, provider: provider)

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: "/root",
                rules: [
                    SearchRuleSelection(field: .textContent, operator: .contains, value: "report")
                ]
            )
        )

        #expect(result.items.map(\.path) == ["/root/report.txt"])
    }

    @Test
    func executeUsesSpotlightForSupportedNameRules() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "hello")
        }
        let expectedPath = URL(fileURLWithPath: fixture.path).appendingPathComponent("report.txt").path
        let provider = SpotlightSearchProvider()
        let walker = DirectoryWalker(providerFactory: { _ in provider })
        let spotlightService = SpotlightSearchService { rootPath, query in
            #expect(rootPath == fixture.path)
            #expect(query.contains("kMDItemFSName"))
            return [expectedPath]
        }
        let executor = SearchExecutor(
            walker: walker,
            provider: provider,
            spotlightSearchService: spotlightService
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [
                    SearchRuleSelection(field: .name, operator: .contains, value: "report")
                ]
            )
        )

        #expect(result.items.map(\.path) == [expectedPath])
    }

    @Test
    func executeMergesSpotlightAndWalkerResultsWhenEnabled() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "hello")
            try builder.file("spotlight-report.txt", contents: "hello")
        }
        let spotlightPath = URL(fileURLWithPath: fixture.path).appendingPathComponent("spotlight-report.txt").path
        let executor = SearchExecutor(
            provider: LocalFilesystemProvider(),
            spotlightSearchService: SpotlightSearchService(runQuery: { _, _ in
                [spotlightPath]
            })
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: true)
        )

        #expect(Set(result.items.map(\.path)) == Set([
            URL(fileURLWithPath: fixture.path).appendingPathComponent("report.txt").path,
            spotlightPath
        ]))
    }

    @Test
    func executeSkipsSpotlightWhenPreferenceDisablesIt() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "hello")
        }
        let executor = SearchExecutor(
            provider: LocalFilesystemProvider(),
            spotlightSearchService: SpotlightSearchService(runQuery: { _, _ in
                Issue.record("Spotlight should not be queried when disabled")
                return []
            })
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
            ),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )

        #expect(result.items.map(\.path) == [URL(fileURLWithPath: fixture.path).appendingPathComponent("report.txt").path])
    }

    @Test
    func executeAnnotatesNameAndExtensionMatchesForHighlighting() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.lookin", contents: "hello")
        }
        let provider = LocalFilesystemProvider()
        let executor = SearchExecutor(
            provider: provider,
            spotlightSearchService: SpotlightSearchService(runQuery: { _, _ in
                throw SpotlightSearchError.queryFailed(status: 1)
            })
        )

        let nameResult = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
            )
        )
        let extensionResult = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .extensionName, operator: .contains, value: "lookin")]
            )
        )

        #expect(nameResult.items.first?.highlightKind == .name)
        #expect(nameResult.items.first?.highlightQuery == "report")
        #expect(extensionResult.items.first?.highlightKind == .extensionName)
        #expect(extensionResult.items.first?.highlightQuery == "lookin")
    }

    @Test
    func executeSkipsResultsInsideExcludedSpecialFolders() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("visible/report.txt", contents: "hello")
            try builder.file("Library/hidden.txt", contents: "hello")
        }
        let storage = InMemoryKeyValueStore()
        let specialFoldersStore = SpecialFoldersStore(storage: storage)
        try specialFoldersStore.save(
            SpecialFoldersConfiguration(
                rules: [SpecialFolderRule(
                    path: URL(fileURLWithPath: fixture.path).appendingPathComponent("Library").path,
                    disposition: .exclude
                )]
            )
        )
        let provider = LocalFilesystemProvider()
        let executor = SearchExecutor(
            provider: provider,
            spotlightSearchService: SpotlightSearchService(runQuery: { _, _ in
                throw SpotlightSearchError.queryFailed(status: 1)
            }),
            specialFoldersStore: specialFoldersStore
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .name, operator: .containsAnyOf, value: "report hidden")]
            )
        )

        #expect(result.items.map(\.path) == [URL(fileURLWithPath: fixture.path).appendingPathComponent("visible/report.txt").path])
    }

    @Test
    func executePrefersSpotlightBackedTextContentResultsWhenAvailable() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("icons/manifest.txt", contents: "size=32x32")
        }
        let expectedPath = URL(fileURLWithPath: fixture.path).appendingPathComponent("icons/manifest.txt").path
        let provider = SpotlightOnlySearchProvider()
        let walker = DirectoryWalker(providerFactory: { _ in provider })
        let spotlightService = SpotlightSearchService { rootPath, query in
            #expect(rootPath == fixture.path)
            #expect(query == "\"32x32\"")
            return [expectedPath]
        }
        let executor = SearchExecutor(
            walker: walker,
            provider: provider,
            spotlightSearchService: spotlightService,
            specialFoldersStore: SpecialFoldersStore(storage: InMemoryKeyValueStore())
        )

        let result = executor.execute(
            request: SearchRequest(
                scopeDescription: "Root",
                rootPath: fixture.path,
                rules: [SearchRuleSelection(field: .textContent, operator: .contains, value: "32x32")]
            )
        )

        #expect(result.items.map(\.path) == [expectedPath])
        #expect(provider.didReadDirectory == false)
    }

    @Test
    func executeSupportsFafDateOperatorsAndKindMatching() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("Preview.app/Contents/Info.plist", contents: "plist")
            try builder.file("today.txt", contents: "hello")
            try builder.file("older.txt", contents: "older")
        }

        let fileManager = FileManager.default
        let bundlePath = URL(fileURLWithPath: fixture.path).appendingPathComponent("Preview.app").path
        let bundleContentsPath = URL(fileURLWithPath: bundlePath).appendingPathComponent("Contents").path
        let plistPath = URL(fileURLWithPath: bundleContentsPath).appendingPathComponent("Info.plist").path
        let todayPath = URL(fileURLWithPath: fixture.path).appendingPathComponent("today.txt").path
        let olderPath = URL(fileURLWithPath: fixture.path).appendingPathComponent("older.txt").path
        let staleBundleDate = ISO8601DateFormatter().date(from: "2026-04-08T08:00:00Z")!
        try fileManager.setAttributes([.modificationDate: ISO8601DateFormatter().date(from: "2026-04-12T08:00:00Z")!], ofItemAtPath: todayPath)
        try fileManager.setAttributes([.modificationDate: ISO8601DateFormatter().date(from: "2026-04-08T08:00:00Z")!], ofItemAtPath: olderPath)
        try fileManager.setAttributes([.modificationDate: staleBundleDate], ofItemAtPath: bundlePath)
        try fileManager.setAttributes([.modificationDate: staleBundleDate], ofItemAtPath: bundleContentsPath)
        try fileManager.setAttributes([.modificationDate: staleBundleDate], ofItemAtPath: plistPath)

        let executor = SearchExecutor(
            provider: LocalFilesystemProvider(),
            spotlightSearchService: SpotlightSearchService(runQuery: { _, _ in [] }),
            nowProvider: { ISO8601DateFormatter().date(from: "2026-04-12T10:00:00Z")! }
        )

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

        #expect(kindResult.items.contains { $0.path.hasSuffix("/Preview.app") })
        #expect(dateResult.items.map(\.path) == [todayPath])
    }
}

private struct FailingSearchProvider: FilesystemAccessProviding {
    let kind: ProviderKind = .local

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

private struct SpotlightSearchProvider: FilesystemAccessProviding {
    let kind: ProviderKind = .local

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        throw SpotlightProviderError.shouldNotWalk
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        [.type: FileAttributeType.typeRegular, .size: NSNumber(value: 6)]
    }

    func contentsOfFile(atPath path: String) throws -> Data {
        Data()
    }
}

private final class SpotlightOnlySearchProvider: FilesystemAccessProviding, @unchecked Sendable {
    let kind: ProviderKind = .local
    var didReadDirectory = false

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        didReadDirectory = true
        return []
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }

    func contentsOfFile(atPath path: String) throws -> Data {
        Issue.record("Filesystem content scan should be skipped when Spotlight satisfies the text search")
        return Data()
    }
}

private enum SpotlightProviderError: Error {
    case shouldNotWalk
}
