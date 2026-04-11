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
        XCTAssertEqual(store.all().last?.compatibility, .full)
        XCTAssertEqual(store.all().last?.criteria?.scope.representedPath, "/tmp")
    }

    func testReadsLegacySummaryOnlySavedSearchRecords() throws {
        let storage = InMemoryKeyValueStore()
        let legacy = [
            LegacySavedSearchFixture(
                name: "旧搜索",
                querySummary: "/tmp",
                createdAt: Date(timeIntervalSince1970: 123)
            )
        ]
        try storage.setCodable(legacy, forKey: "savedSearches")

        let store = SavedSearchStore(storage: storage)
        let searches = store.all()

        XCTAssertEqual(searches.map(\.name), ["旧搜索"])
        XCTAssertEqual(searches.first?.compatibility, .legacySummary)
        XCTAssertNil(searches.first?.criteria)
    }

    func testPersistsFullCriteriaAndPresentationState() throws {
        let store = SavedSearchStore(storage: InMemoryKeyValueStore())
        let criteria = SearchCriteriaSnapshot(
            scope: SearchScopeSnapshot(
                title: "inside Downloads",
                representedPath: "/Users/test/Downloads",
                scopeDescription: "Downloads",
                sourceKind: .folder
            ),
            rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
        )
        let presentation = ResultPresentationState(mode: .table, sortField: .dateModified)

        try store.save(name: "报告搜索", criteria: criteria, presentationState: presentation)

        let saved = try XCTUnwrap(store.all().first)
        XCTAssertEqual(saved.compatibility, .full)
        XCTAssertEqual(saved.criteria, criteria)
        XCTAssertEqual(saved.presentationState, presentation)
    }
}

private struct LegacySavedSearchFixture: Codable {
    let name: String
    let querySummary: String
    let createdAt: Date
}
