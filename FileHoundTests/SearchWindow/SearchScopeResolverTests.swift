import Foundation
import Testing
@testable import FileHound

struct SearchScopeResolverTests {
    private let volumes = [
        SearchScopeVolume(path: "/Volumes/External", isLocal: true),
        SearchScopeVolume(path: "/Volumes/Share", isLocal: false)
    ]

    private func preset(_ preset: SearchScopePreset) -> SearchScopeSnapshot {
        SearchScopeSnapshot(title: "", representedPath: "/", scopeDescription: preset.rawValue, sourceKind: .preset)
    }

    private func resolver(finderSelection: [String]? = nil) -> SearchScopeResolver {
        SearchScopeResolver(mountedVolumes: { volumes }, finderSelection: { finderSelection })
    }

    @Test
    func presetsResolveToDistinctRoots() {
        let startup = resolver().resolve(preset(.startupVolume))
        #expect(startup.rootPaths == ["/"])
        #expect(startup.excludedPaths.contains("/Volumes"))
        #expect(startup.excludedPaths.contains("/System/Volumes"))

        #expect(resolver().resolve(preset(.allDisks)).rootPaths == ["/", "/Volumes/External", "/Volumes/Share"])
        #expect(resolver().resolve(preset(.localDisks)).rootPaths == ["/", "/Volumes/External"])
        #expect(resolver().resolve(preset(.networkVolumes)).rootPaths == ["/Volumes/Share"])
    }

    @Test
    func finderSelectionUsesSelectedFoldersOrFallsBackToHome() {
        #expect(resolver(finderSelection: ["/tmp/a", "/tmp/b"]).resolve(preset(.finderSelection)).rootPaths == ["/tmp/a", "/tmp/b"])
        #expect(resolver(finderSelection: nil).resolve(preset(.finderSelection)).rootPaths == [NSHomeDirectory()])
    }

    @Test
    func foldersResolveToTheirOwnPath() {
        let folder = SearchScopeSnapshot(title: "", representedPath: "/tmp/x", scopeDescription: "x", sourceKind: .folder)
        #expect(resolver().resolve(folder) == ResolvedSearchScope(rootPaths: ["/tmp/x"], excludedPaths: []))
    }

    @Test
    func finderScriptOutputPrefersSelectedFolders() {
        let isDirectory: (String) -> Bool = { $0.hasPrefix("/dir") }
        #expect(FinderSelectionReader.folderPaths(
            fromScriptOutput: "/dir/a/\n/file.txt\n@insertion:/dir/window/",
            isDirectory: isDirectory
        ) == ["/dir/a"])
        #expect(FinderSelectionReader.folderPaths(
            fromScriptOutput: "/file.txt\n@insertion:/dir/window/",
            isDirectory: isDirectory
        ) == ["/dir/window"])
    }

    @Test
    func executorSearchesEveryRootAndSkipsExcludedPaths() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("one/match.txt", contents: "1")
            try builder.file("two/match.txt", contents: "2")
            try builder.file("two/skip/match.txt", contents: "3")
            try builder.file("three/match.txt", contents: "4")
        }
        let root = fixture.path
        let executor = SearchExecutor(spotlightSearchService: SpotlightSearchService(runQuery: { _, _ in [] }))
        let request = SearchRequest(
            scopeDescription: SearchScopePreset.allDisks.rawValue,
            rootPaths: [root + "/one", root + "/two"],
            excludedPaths: [root + "/two/skip"],
            rules: [
                SearchRuleSelection(field: .name, operator: .isExactly, value: "match.txt"),
                SearchRuleSelection(field: .limitFolderDepth, operator: .isExactly, value: "1")
            ]
        )

        let paths = executor.execute(request: request, options: SearchExecutionOptions(includeSpotlightResults: false))
            .items.map { String($0.path.dropFirst(root.count + 1)) }.sorted()
        #expect(paths == ["one/match.txt", "two/match.txt"])
    }
}
