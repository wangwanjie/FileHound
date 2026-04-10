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

private enum SpotlightProviderError: Error {
    case shouldNotWalk
}
