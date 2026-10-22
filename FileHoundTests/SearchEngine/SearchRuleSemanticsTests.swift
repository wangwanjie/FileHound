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
        let executor = SearchExecutor.hermetic(
            walker: walker,
            spotlight: spotlight ?? SpotlightSearchService(runQuery: { _, _ in [] })
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
        let recorder = ListingRecordingProvider()
        let walker = DirectoryWalker(provider: recorder)
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
        let emptyWalker = DirectoryWalker(provider: EmptyListingProvider())

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
    func fileSizeParsingUsesFinderUnitsAndThousandsSeparators() {
        #expect(SearchRuleNumberParser.parseByteCount("500") == 500)
        // 与访达一致：KB/MB/GB 按 1000 进制，KiB/MiB/GiB 按 1024 进制
        #expect(SearchRuleNumberParser.parseByteCount("10 KB") == 10_000)
        #expect(SearchRuleNumberParser.parseByteCount("10 KiB") == 10_240)
        #expect(SearchRuleNumberParser.parseByteCount("1.5mb") == 1_500_000)
        #expect(SearchRuleNumberParser.parseByteCount("2G") == 2_000_000_000)
        #expect(SearchRuleNumberParser.parseByteCount("2 GiB") == 2_147_483_648)
        #expect(SearchRuleNumberParser.parseByteCount("1 TiB") == 1_099_511_627_776)
        // 千分位逗号不是小数点；只有逗号且后面不是恰好三位数字时才按小数点处理
        #expect(SearchRuleNumberParser.parseByteCount("1,024") == 1_024)
        #expect(SearchRuleNumberParser.parseByteCount("1,024,000 bytes") == 1_024_000)
        #expect(SearchRuleNumberParser.parseByteCount("1,5 MB") == 1_500_000)
        #expect(SearchRuleNumberParser.parseByteCount("1,234.5 KB") == 1_234_500)
        #expect(SearchRuleNumberParser.parseByteCount("1.234,5 KB") == 1_234_500)
        #expect(SearchRuleNumberParser.parseByteCount("abc") == nil)
        #expect(SearchRuleNumberParser.parseByteCount("10 parsecs") == nil)
        #expect(SearchRuleNumberParser.parseByteCount("1.2.3") == nil)
        // 超出 Int64 范围时返回 nil，不能在编辑校验时溢出崩溃
        #expect(SearchRuleNumberParser.parseByteCount("99999999999999999999") == nil)
        #expect(SearchRuleNumberParser.parseByteCount("10000000 TB") == nil)
        #expect(SearchRuleNumberParser.parseByteCount("9000000 TB") == 9_000_000_000_000_000_000)

        let validator = SearchRuleValidator()
        #expect(validator.validate(SearchRuleSelection(field: .fileSize, operator: .isGreaterThan, value: "abc")) == .invalid(messageKey: "search_rule.validation.size_invalid"))
        #expect(validator.validate(SearchRuleSelection(field: .fileSize, operator: .isGreaterThan, value: "99999999999999999999")) == .invalid(messageKey: "search_rule.validation.size_invalid"))
        #expect(validator.validate(SearchRuleSelection(field: .fileSize, operator: .isGreaterThan, value: "10 MB")) == .valid)
        #expect(validator.validate(SearchRuleSelection(field: .limitAmount, operator: .isExactly, value: "1.5")) == .invalid(messageKey: "search_rule.validation.integer_invalid"))
    }

    @Test
    func fileSizeRulesCompareDecimalUnits() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("thousand.bin", contents: String(repeating: "a", count: 1_000))
            try builder.file("kibibyte.bin", contents: String(repeating: "a", count: 1_024))
        }

        #expect(run([SearchRuleSelection(field: .fileSize, operator: .isExactly, value: "1 KB")], in: fixture) == ["thousand.bin"])
        #expect(run([SearchRuleSelection(field: .fileSize, operator: .isExactly, value: "1 KiB")], in: fixture) == ["kibibyte.bin"])
        #expect(run([SearchRuleSelection(field: .fileSize, operator: .isGreaterThan, value: "1,000")], in: fixture) == ["kibibyte.bin"])
    }
}

struct CommentAndScriptRuleTests {
    private func run(_ rules: [SearchRuleSelection], in fixture: TemporaryFixtureTree) -> [String] {
        let executor = SearchExecutor.hermetic()
        let result = executor.execute(
            request: SearchRequest(scopeDescription: "Root", rootPath: fixture.path, rules: rules),
            options: SearchExecutionOptions(includeSpotlightResults: false)
        )
        return result.items.map { String($0.path.dropFirst(fixture.path.count + 1)) }.sorted()
    }

    private func setFinderComment(_ comment: String, atPath path: String) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: comment, format: .binary, options: 0)
        let status = data.withUnsafeBytes { buffer in
            setxattr(path, FinderCommentReader.extendedAttributeName, buffer.baseAddress, data.count, 0, 0)
        }
        #expect(status == 0)
    }

    @Test
    func commentsRuleMatchesFinderComments() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("invoice.pdf", contents: "a")
            try builder.file("photo.jpg", contents: "b")
        }
        try setFinderComment("Paid in March", atPath: fixture.rootURL.appendingPathComponent("invoice.pdf").path)

        #expect(FinderCommentReader.comment(atPath: fixture.rootURL.appendingPathComponent("invoice.pdf").path) == "Paid in March")
        #expect(run([SearchRuleSelection(field: .comments, operator: .contains, value: "paid")], in: fixture) == ["invoice.pdf"])
        #expect(run([
            SearchRuleSelection(field: .comments, operator: .doesNotContain, value: "paid"),
            SearchRuleSelection(field: .name, operator: .contains, value: ".")
        ], in: fixture) == ["photo.jpg"])
    }

    @Test
    func scriptRuleMatchesTextScriptSources() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("deploy.sh", contents: "#!/bin/sh\nrsync -av build/ server:/srv\n")
            try builder.file("run", contents: "#!/usr/bin/env python3\nimport rsync\n")
            try builder.file("notes.txt", contents: "rsync is great")
        }

        #expect(run([SearchRuleSelection(field: .script, operator: .containsPhrase, value: "rsync")], in: fixture) == ["deploy.sh", "run"])
        #expect(run([SearchRuleSelection(field: .script, operator: .matchesRegex, value: "import\\s+rsync")], in: fixture) == ["run"])
        #expect(run([SearchRuleSelection(field: .script, operator: .doesNotMatchRegex, value: "python")], in: fixture) == ["deploy.sh"])
    }

    @Test
    func compiledScriptsAreDecompiled() {
        let reader = ScriptSourceReader(decompile: { path in path.hasSuffix(".scpt") ? "tell application \"Finder\" to activate" : nil })
        let source = reader.source(atPath: "/tmp/a.scpt", isDirectory: false, fileSize: 10, readContents: { _ in Data() })
        #expect(source == "tell application \"Finder\" to activate")
        #expect(reader.source(atPath: "/tmp/a.txt", isDirectory: false, fileSize: 3, readContents: { _ in Data("abc".utf8) }) == nil)
    }
}
