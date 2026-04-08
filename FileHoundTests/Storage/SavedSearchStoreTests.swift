import XCTest
@testable import FileHound

final class SavedSearchStoreTests: XCTestCase {
    func testPersistsSavedSearchNamesInInsertionOrder() throws {
        let store = SavedSearchStore(storage: InMemoryKeyValueStore())
        let query = SearchQuery(
            scope: .roots(["/tmp"]),
            rootGroup: .all([.rule(.nameContains("log"))])
        )

        try store.save(name: "日志排查", query: query)
        try store.save(name: "源码扫描", query: query)

        XCTAssertEqual(store.all().map(\.name), ["日志排查", "源码扫描"])
    }
}
