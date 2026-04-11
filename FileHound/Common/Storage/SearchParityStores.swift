import Foundation

final class SearchHistoryStore {
    static let shared = SearchHistoryStore(storage: MMKVKeyValueStore.shared)

    private let storage: KeyValueStoring
    private let key = "recentSearches.v1"
    private let limit: Int

    init(storage: KeyValueStoring = MMKVKeyValueStore.shared, limit: Int = 20) {
        self.storage = storage
        self.limit = max(limit, 1)
    }

    func all() -> [RecentSearchRecord] {
        (try? storage.codableValue([RecentSearchRecord].self, forKey: key)) ?? []
    }

    func record(_ entry: RecentSearchRecord) throws {
        var entries = all()
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        try storage.setCodable(entries, forKey: key)
    }
}

final class RecentLocationStore {
    static let shared = RecentLocationStore(storage: MMKVKeyValueStore.shared)

    private let storage: KeyValueStoring
    private let key = "recentLocations.v1"
    private let limit: Int

    init(storage: KeyValueStoring = MMKVKeyValueStore.shared, limit: Int = 10) {
        self.storage = storage
        self.limit = max(limit, 1)
    }

    func all() -> [RecentLocationRecord] {
        let entries = (try? storage.codableValue([RecentLocationRecord].self, forKey: key)) ?? []
        let normalizedEntries = normalized(entries)
        if normalizedEntries != entries {
            try? storage.setCodable(normalizedEntries, forKey: key)
        }
        return normalizedEntries
    }

    func remember(scope: SearchScopeSnapshot, usedAt: Date = Date()) throws {
        guard let representedPath = scope.representedPath, representedPath.isEmpty == false else {
            return
        }

        var entries = all()
        entries.removeAll { $0.scope.representedPath == representedPath }
        entries.insert(RecentLocationRecord(scope: scope, lastUsedAt: usedAt), at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        try storage.setCodable(normalized(entries), forKey: key)
    }

    private func normalized(_ entries: [RecentLocationRecord]) -> [RecentLocationRecord] {
        var seenPaths = Set<String>()
        var deduplicatedEntries: [RecentLocationRecord] = []

        for entry in entries {
            let dedupeKey = entry.scope.representedPath ?? "\(entry.scope.sourceKind.rawValue)|\(entry.scope.title)"
            guard seenPaths.insert(dedupeKey).inserted else {
                continue
            }
            deduplicatedEntries.append(entry)
        }

        return Array(deduplicatedEntries.prefix(limit))
    }
}

final class SearchSessionStore {
    static let shared = SearchSessionStore(storage: MMKVKeyValueStore.shared)

    private let storage: KeyValueStoring
    private let key = "searchSessionSnapshot.v1"

    init(storage: KeyValueStoring = MMKVKeyValueStore.shared) {
        self.storage = storage
    }

    func load() -> SearchSessionSnapshot? {
        try? storage.codableValue(SearchSessionSnapshot.self, forKey: key)
    }

    func save(_ snapshot: SearchSessionSnapshot) throws {
        try storage.setCodable(snapshot, forKey: key)
    }
}

final class SpecialFoldersStore: @unchecked Sendable {
    static let shared = SpecialFoldersStore(storage: MMKVKeyValueStore.shared)

    private let storage: KeyValueStoring
    private let key = "specialFolders.v1"

    init(storage: KeyValueStoring = MMKVKeyValueStore.shared) {
        self.storage = storage
    }

    func load() -> SpecialFoldersConfiguration {
        (try? storage.codableValue(SpecialFoldersConfiguration.self, forKey: key)) ?? .empty
    }

    func save(_ configuration: SpecialFoldersConfiguration) throws {
        try storage.setCodable(configuration, forKey: key)
    }
}
