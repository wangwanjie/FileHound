import Foundation
import Testing
@testable import FileHound

struct SearchRuleSemanticsTests {
    private func run(
        _ rules: [SearchRuleSelection],
        in fixture: TemporaryFixtureTree,
        walker: DirectoryWalker = DirectoryWalker(),
        spotlight: SpotlightSearchService? = nil
    ) -> [String] {
        let executor = SearchExecutor(
            walker: walker,
            provider: LocalFilesystemProvider(),
            spotlightSearchService: spotlight ?? SpotlightSearchService(runQuery: { _, _ in [] })
        )
        let result = executor.execute(
            request: SearchRequest(scopeDescription: "Root", rootPath: fixture.path, rules: rules),
            options: SearchExecutionOptions(includeSpotlightResults: spotlight != nil)
        )
        return result.items.map { String($0.path.dropFirst(fixture.path.count + 1)) }.sorted()
    }

    @Test
    func folderNamesMatchIndividualPathComponents() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("src/lib/a.txt", contents: "a")
            try builder.file("mysrc/b.txt", contents: "b")
        }

        let exact = run([
            SearchRuleSelection(field: .folderNames, operator: .isExactly, value: "src"),
            SearchRuleSelection(field: .name, operator: .endsWith, value: ".txt")
        ], in: fixture)
        #expect(exact == ["src/lib/a.txt"])

        let begins = run([
            SearchRuleSelection(field: .folderNames, operator: .beginsWith, value: "li"),
            SearchRuleSelection(field: .name, operator: .endsWith, value: ".txt")
        ], in: fixture)
        #expect(begins == ["src/lib/a.txt"])

        let excluded = run([
            SearchRuleSelection(field: .folderNames, operator: .isNot, value: "lib"),
            SearchRuleSelection(field: .name, operator: .endsWith, value: ".txt")
        ], in: fixture)
        #expect(excluded == ["mysrc/b.txt"])
    }

    @Test
    func tagRulesMatchAnySingleTag() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("tagged.txt", contents: "a")
            try builder.file("plain.txt", contents: "b")
        }
        try (fixture.rootURL.appendingPathComponent("tagged.txt") as NSURL)
            .setResourceValue(["Work", "Red"], forKey: .tagNamesKey)

        #expect(run([SearchRuleSelection(field: .tag, operator: .isExactly, value: "Red")], in: fixture) == ["tagged.txt"])
        #expect(run([SearchRuleSelection(field: .tag, operator: .isNot, value: "Red")], in: fixture) == ["plain.txt"])
    }

    @Test
    func phraseAndWordOperatorsRespectWordBoundaries() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("annual report.txt", contents: "a")
            try builder.file("export notes.txt", contents: "b")
        }

        #expect(run([SearchRuleSelection(field: .name, operator: .containsPhrase, value: "port")], in: fixture).isEmpty)
        #expect(run([SearchRuleSelection(field: .name, operator: .containsPhrase, value: "annual report")], in: fixture) == ["annual report.txt"])
        #expect(run([SearchRuleSelection(field: .name, operator: .containsWords, value: "notes export")], in: fixture) == ["export notes.txt"])
        #expect(run([SearchRuleSelection(field: .name, operator: .contains, value: "port")], in: fixture).count == 2)
    }

    @Test
    func folderDepthOperatorsAndPruning() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("one.txt", contents: "1")
            try builder.file("a/two.txt", contents: "2")
            try builder.file("a/b/three.txt", contents: "3")
        }
        let recorder = ListingRecorder()
        let walker = DirectoryWalker(providerFactory: { _ in recorder })
        let txt = SearchRuleSelection(field: .name, operator: .endsWith, value: ".txt")

        #expect(run([txt, SearchRuleSelection(field: .limitFolderDepth, operator: .isExactly, value: "1")], in: fixture, walker: walker) == ["one.txt"])
        #expect(recorder.listedPaths.contains { $0.hasSuffix("/a") } == false)

        #expect(run([txt, SearchRuleSelection(field: .limitFolderDepth, operator: .isLessThan, value: "3")], in: fixture) == ["a/two.txt", "one.txt"])
        #expect(run([txt, SearchRuleSelection(field: .limitFolderDepth, operator: .isGreaterThan, value: "2")], in: fixture) == ["a/b/three.txt"])
        #expect(run([txt, SearchRuleSelection(field: .limitAmount, operator: .isLessThan, value: "3")], in: fixture).count == 2)
    }

    @Test
    func spotlightCandidatesAreRecheckedAgainstRules() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("Report.txt", contents: "a")
        }
        let path = fixture.rootURL.appendingPathComponent("Report.txt").path
        let spotlight = SpotlightSearchService(runQuery: { _, _ in [path] })
        let emptyWalker = DirectoryWalker(providerFactory: { _ in EmptyProvider() })

        let insensitive = run(
            [SearchRuleSelection(field: .name, operator: .contains, value: "report")],
            in: fixture, walker: emptyWalker, spotlight: spotlight
        )
        #expect(insensitive == ["Report.txt"])

        let sensitive = run(
            [
                SearchRuleSelection(field: .name, operator: .contains, value: "report"),
                SearchRuleSelection(field: .caseSensitive, operator: .isExactly, value: "true")
            ],
            in: fixture, walker: emptyWalker, spotlight: spotlight
        )
        #expect(sensitive.isEmpty)
    }

    @Test
    func fileSizeParsingAndValidation() {
        #expect(SearchRuleNumberParser.parseByteCount("500") == 500)
        #expect(SearchRuleNumberParser.parseByteCount("10 KB") == 10_240)
        #expect(SearchRuleNumberParser.parseByteCount("1.5mb") == 1_572_864)
        #expect(SearchRuleNumberParser.parseByteCount("2G") == 2_147_483_648)
        #expect(SearchRuleNumberParser.parseByteCount("abc") == nil)
        #expect(SearchRuleNumberParser.parseByteCount("10 parsecs") == nil)

        let validator = SearchRuleValidator()
        #expect(validator.validate(SearchRuleSelection(field: .fileSize, operator: .isGreaterThan, value: "abc")) == .invalid(messageKey: "search_rule.validation.size_invalid"))
        #expect(validator.validate(SearchRuleSelection(field: .fileSize, operator: .isGreaterThan, value: "10 MB")) == .valid)
        #expect(validator.validate(SearchRuleSelection(field: .limitAmount, operator: .isExactly, value: "1.5")) == .invalid(messageKey: "search_rule.validation.integer_invalid"))
    }
}

private final class ListingRecorder: FilesystemAccessProviding, @unchecked Sendable {
    let kind: ProviderKind = .local
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

private struct EmptyProvider: FilesystemAccessProviding {
    let kind: ProviderKind = .local

    func contentsOfDirectory(atPath path: String) throws -> [String] { [] }
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }
    func contentsOfFile(atPath path: String) throws -> Data { Data() }
}
