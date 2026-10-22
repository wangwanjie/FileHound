import Foundation
import Testing
@testable import FileHound

struct SearchParityStoresTests {
    @Test
    func recentLocationStoreDeduplicatesAndLimitsEntries() throws {
        let storage = InMemoryKeyValueStore()
        let store = RecentLocationStore(storage: storage, limit: 2)

        try store.remember(
            scope: SearchScopeSnapshot(
                title: "inside Downloads",
                representedPath: "/Users/test/Downloads",
                scopeDescription: "Downloads",
                sourceKind: .folder
            ),
            usedAt: Date(timeIntervalSince1970: 10)
        )
        try store.remember(
            scope: SearchScopeSnapshot(
                title: "inside Documents",
                representedPath: "/Users/test/Documents",
                scopeDescription: "Documents",
                sourceKind: .folder
            ),
            usedAt: Date(timeIntervalSince1970: 20)
        )
        try store.remember(
            scope: SearchScopeSnapshot(
                title: "inside Downloads",
                representedPath: "/Users/test/Downloads",
                scopeDescription: "Downloads",
                sourceKind: .recentLocation
            ),
            usedAt: Date(timeIntervalSince1970: 30)
        )

        let entries = store.all()

        #expect(entries.count == 2)
        #expect(entries.map { $0.scope.representedPath } == ["/Users/test/Downloads", "/Users/test/Documents"])
        #expect(entries.first?.scope.sourceKind == .recentLocation)
    }

    @Test
    func recentLocationStoreSanitizesLegacyDuplicateRecordsOnRead() throws {
        let storage = InMemoryKeyValueStore()
        let store = RecentLocationStore(storage: storage, limit: 10)
        let records = [
            RecentLocationRecord(
                scope: SearchScopeSnapshot(
                    title: "on Shared",
                    representedPath: "/Volumes/Shared",
                    scopeDescription: "Shared",
                    sourceKind: .mountedVolume
                ),
                lastUsedAt: Date(timeIntervalSince1970: 30)
            ),
            RecentLocationRecord(
                scope: SearchScopeSnapshot(
                    title: "inside Shared",
                    representedPath: "/Volumes/Shared",
                    scopeDescription: "Shared",
                    sourceKind: .recentLocation
                ),
                lastUsedAt: Date(timeIntervalSince1970: 20)
            )
        ]
        try storage.setCodable(records, forKey: "recentLocations.v1")

        let entries = store.all()

        #expect(entries.count == 1)
        #expect(entries.first?.scope.representedPath == "/Volumes/Shared")
    }

    @Test
    func searchSessionStoreRoundTripsSnapshots() throws {
        let storage = InMemoryKeyValueStore()
        let store = SearchSessionStore(storage: storage)
        let snapshot = SearchSessionSnapshot(
            criteria: SearchCriteriaSnapshot(
                scope: SearchScopeSnapshot(
                    title: "on startup volume",
                    representedPath: "/",
                    scopeDescription: "Macintosh HD",
                    sourceKind: .preset
                ),
                rules: [SearchRuleSelection(field: .name, operator: .contains, value: "report")]
            ),
            presentationState: ResultPresentationState(mode: .table, sortField: .path)
        )

        try store.save(snapshot)

        #expect(store.load() == snapshot)
    }

    @Test
    func specialFoldersStoreRoundTripsConfiguration() throws {
        let storage = InMemoryKeyValueStore()
        let store = SpecialFoldersStore(storage: storage)
        let configuration = SpecialFoldersConfiguration(
            rules: [
                SpecialFolderRule(path: "/Users/test/Library", disposition: .exclude),
                SpecialFolderRule(path: "/Users/test/Downloads", disposition: .slowSearch)
            ]
        )

        try store.save(configuration)

        #expect(store.load() == configuration)
    }

    @Test
    func searchHistoryKeepsIntactRecordsWhenOneIsCorrupted() throws {
        let storage = InMemoryKeyValueStore()
        let store = SearchHistoryStore(storage: storage)
        try store.record(RecentSearchRecord(title: "旧一", criteria: makeCriteria("a")))
        try store.record(RecentSearchRecord(title: "旧二", criteria: makeCriteria("b")))
        let corrupted = try insertingCorruptedElement(into: storage, key: "recentSearches.v1")

        #expect(store.all().map(\.title) == ["旧二", "旧一"])

        // 以前解码失败返回 []，下一次记录会覆盖全部历史
        try store.record(RecentSearchRecord(title: "新", criteria: makeCriteria("c")))
        #expect(store.all().map(\.title) == ["新", "旧二", "旧一"])
        #expect(storage.data(forKey: "recentSearches.v1.backup") == corrupted)
    }

    @Test
    func recentLocationStoreSkipsCorruptedRecords() throws {
        let storage = InMemoryKeyValueStore()
        let store = RecentLocationStore(storage: storage)
        try store.remember(
            scope: SearchScopeSnapshot(title: "Downloads", representedPath: "/Users/test/Downloads", scopeDescription: "Downloads", sourceKind: .folder)
        )
        let corrupted = try insertingCorruptedElement(into: storage, key: "recentLocations.v1")

        #expect(store.all().map(\.scope.representedPath) == ["/Users/test/Downloads"])
        // 读取路径不静默改写有损数据
        #expect(storage.data(forKey: "recentLocations.v1") == corrupted)

        try store.remember(
            scope: SearchScopeSnapshot(title: "Desktop", representedPath: "/Users/test/Desktop", scopeDescription: "Desktop", sourceKind: .folder)
        )
        #expect(store.all().map(\.scope.representedPath) == ["/Users/test/Desktop", "/Users/test/Downloads"])
        #expect(storage.data(forKey: "recentLocations.v1.backup") == corrupted)
    }

    @Test
    func specialFoldersStoreKeepsIntactRulesAndBacksUpBeforeSaving() throws {
        let storage = InMemoryKeyValueStore()
        let store = SpecialFoldersStore(storage: storage)
        try store.save(SpecialFoldersConfiguration(rules: [
            SpecialFolderRule(path: "/Users/test/Library", disposition: .exclude),
            SpecialFolderRule(path: "/Users/test/Downloads", disposition: .slowSearch)
        ]))

        // 一条规则的 disposition 为未知值（例如新版本写入）
        let original = try #require(storage.data(forKey: "specialFolders.v1"))
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var rules = try #require(object["rules"] as? [Any])
        rules.append(["id": UUID().uuidString, "path": "/Users/test/Future", "disposition": "futureMode"])
        object["rules"] = rules
        let corrupted = try JSONSerialization.data(withJSONObject: object)
        storage.set(corrupted, forKey: "specialFolders.v1")

        let loaded = store.load()
        #expect(loaded.rules.map(\.path) == ["/Users/test/Library", "/Users/test/Downloads"])

        // 编辑器基于 load() 保存时，原始数据先被备份
        var edited = loaded
        edited.rules.removeLast()
        try store.save(edited)
        #expect(storage.data(forKey: "specialFolders.v1.backup") == corrupted)
        #expect(store.load().rules.map(\.path) == ["/Users/test/Library"])
    }

    @Test
    func specialFoldersStoreBacksUpUndecodableConfiguration() throws {
        let storage = InMemoryKeyValueStore()
        let garbage = Data("[1, 2".utf8)
        storage.set(garbage, forKey: "specialFolders.v1")
        let store = SpecialFoldersStore(storage: storage)

        #expect(store.load() == .empty)
        try store.save(SpecialFoldersConfiguration(rules: [SpecialFolderRule(path: "/tmp", disposition: .exclude)]))

        #expect(storage.data(forKey: "specialFolders.v1.backup") == garbage)
    }
}

private func makeCriteria(_ value: String) -> SearchCriteriaSnapshot {
    SearchCriteriaSnapshot(
        scope: SearchScopeSnapshot(title: "Home", representedPath: "/tmp", scopeDescription: "Home", sourceKind: .folder),
        rules: [SearchRuleSelection(field: .name, operator: .contains, value: value)]
    )
}

/// 在存储的 JSON 数组中间插入一个无法解码的元素，返回写入后的原始数据
private func insertingCorruptedElement(into storage: InMemoryKeyValueStore, key: String) throws -> Data {
    let original = try #require(storage.data(forKey: key))
    var elements = try #require(JSONSerialization.jsonObject(with: original) as? [Any])
    elements.insert(["unexpected": true], at: min(1, elements.count))
    let corrupted = try JSONSerialization.data(withJSONObject: elements)
    storage.set(corrupted, forKey: key)
    return corrupted
}
