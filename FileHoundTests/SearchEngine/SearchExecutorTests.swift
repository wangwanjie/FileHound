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
