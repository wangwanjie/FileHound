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
}
