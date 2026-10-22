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

    func testDeletesAndRenamesSavedSearches() throws {
        let store = SavedSearchStore(storage: InMemoryKeyValueStore())
        let query = SearchQuery(scope: .roots(["/tmp"]), rootGroup: .all([.rule(.nameContains("log"))]))
        try store.save(name: "甲", query: query)
        try store.save(name: "乙", query: query)

        let first = try XCTUnwrap(store.all().first)
        try store.rename(first, to: "  丙  ")
        XCTAssertEqual(store.all().map(\.name), ["丙", "乙"])
        XCTAssertEqual(store.all().first?.criteria, first.criteria)

        let renamed = try XCTUnwrap(store.all().first)
        try store.rename(renamed, to: "   ")
        XCTAssertEqual(store.all().map(\.name), ["丙", "乙"])

        try store.delete(renamed)
        XCTAssertEqual(store.all().map(\.name), ["乙"])
        try store.delete(renamed)
        XCTAssertEqual(store.all().map(\.name), ["乙"])
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

    func testCorruptedEntriesDoNotLoseOtherSavedSearches() throws {
        let storage = InMemoryKeyValueStore()
        let store = SavedSearchStore(storage: storage)
        let criteria = SearchCriteriaSnapshot(
            scope: SearchScopeSnapshot(title: "Home", representedPath: "/tmp", scopeDescription: "Home", sourceKind: .folder),
            rules: [SearchRuleSelection(field: .name, operator: .contains, value: "a")]
        )
        try store.save(name: "完好一", criteria: criteria)
        try store.save(name: "完好二", criteria: criteria)

        // 注入两个坏元素：一个完全无法解码，一个条件损坏但仍有摘要字段（降级为仅摘要）
        let original = try XCTUnwrap(storage.data(forKey: "savedSearches"))
        var elements = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [Any])
        elements.insert(["unexpected": 1], at: 1)
        elements.append(["name": "条件损坏", "querySummary": "/tmp", "createdAt": 0, "criteria": "broken"])
        let corrupted = try JSONSerialization.data(withJSONObject: elements)
        storage.set(corrupted, forKey: "savedSearches")

        let loaded = store.all()
        XCTAssertEqual(loaded.map(\.name), ["完好一", "完好二", "条件损坏"])
        XCTAssertEqual(loaded[0].criteria, criteria)
        XCTAssertEqual(loaded[1].criteria, criteria)
        XCTAssertEqual(loaded[2].compatibility, .legacySummary)
        XCTAssertNil(storage.data(forKey: "savedSearches.backup"), "只读不应产生备份")

        // 写操作前先备份原始数据，写回后其他完好条目的条件不丢失
        try store.save(name: "新增", criteria: criteria)
        XCTAssertEqual(storage.data(forKey: "savedSearches.backup"), corrupted)
        XCTAssertEqual(store.all().map(\.name), ["完好一", "完好二", "条件损坏", "新增"])
        XCTAssertEqual(store.all().first?.criteria, criteria)
    }

    func testUndecodableBlobIsBackedUpBeforeBeingOverwritten() throws {
        let storage = InMemoryKeyValueStore()
        let garbage = Data("{not json".utf8)
        storage.set(garbage, forKey: "savedSearches")
        let store = SavedSearchStore(storage: storage)

        XCTAssertEqual(store.all(), [])
        try store.save(name: "新增", query: SearchQuery(scope: .roots(["/tmp"]), rootGroup: .all([.rule(.nameContains("log"))])))

        XCTAssertEqual(storage.data(forKey: "savedSearches.backup"), garbage)
        XCTAssertEqual(store.all().map(\.name), ["新增"])
    }

    func testCleanDataIsNotBackedUp() throws {
        let storage = InMemoryKeyValueStore()
        let store = SavedSearchStore(storage: storage)
        let query = SearchQuery(scope: .roots(["/tmp"]), rootGroup: .all([.rule(.nameContains("log"))]))

        try store.save(name: "甲", query: query)
        try store.save(name: "乙", query: query)

        XCTAssertNil(storage.data(forKey: "savedSearches.backup"))
    }
}

private struct LegacySavedSearchFixture: Codable {
    let name: String
    let querySummary: String
    let createdAt: Date
}
