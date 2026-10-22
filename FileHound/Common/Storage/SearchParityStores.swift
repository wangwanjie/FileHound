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
        storage.lenientArray(RecentSearchRecord.self, forKey: key).elements
    }

    func record(_ entry: RecentSearchRecord) throws {
        // 同一组条件只保留最新一次，避免重复搜索占满菜单
        var entries = entriesForWriting().filter { $0.criteria != entry.criteria }
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        try storage.setCodable(entries, forKey: key)
    }

    func removeAll() throws {
        // 用户主动清空；若原数据有损仍先备份，保持「有损数据写回前必备份」的一致约定
        _ = entriesForWriting()
        try storage.setCodable([RecentSearchRecord](), forKey: key)
    }

    /// 写回前读取：坏元素被跳过（或整体无法解码）时先备份原始数据，避免下一次记录覆盖全部历史
    private func entriesForWriting() -> [RecentSearchRecord] {
        let loaded = storage.lenientArray(RecentSearchRecord.self, forKey: key)
        if loaded.isLossy {
            storage.backupRawValue(forKey: key)
        }
        return loaded.elements
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
        let loaded = storage.lenientArray(RecentLocationRecord.self, forKey: key)
        let normalizedEntries = normalized(loaded.elements)
        // 原数据有坏元素时不在读取路径上静默改写，留给真正的写操作（先备份再写回）
        if loaded.isLossy == false, normalizedEntries != loaded.elements {
            try? storage.setCodable(normalizedEntries, forKey: key)
        }
        return normalizedEntries
    }

    func remember(scope: SearchScopeSnapshot, usedAt: Date = Date()) throws {
        guard let representedPath = scope.representedPath, representedPath.isEmpty == false else {
            return
        }

        let loaded = storage.lenientArray(RecentLocationRecord.self, forKey: key)
        if loaded.isLossy {
            // 有坏元素时写回前先备份原始数据
            storage.backupRawValue(forKey: key)
        }
        var entries = normalized(loaded.elements)
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
        loadConfiguration().configuration
    }

    func save(_ configuration: SpecialFoldersConfiguration) throws {
        // 编辑器基于 load() 的结果保存；若原数据有坏规则被跳过（或整体无法解码），先备份原始数据，避免清空用户配置
        if loadConfiguration().isLossy {
            storage.backupRawValue(forKey: key)
        }
        try storage.setCodable(configuration, forKey: key)
    }

    /// 逐条宽容解码规则：跳过无法解码的单条规则，保留其余规则
    private func loadConfiguration() -> (configuration: SpecialFoldersConfiguration, isLossy: Bool) {
        guard let data = storage.data(forKey: key) else {
            return (.empty, false)
        }
        guard let stored = try? JSONDecoder().decode(LenientSpecialFoldersConfiguration.self, from: data) else {
            return (.empty, true)
        }
        let rules = stored.rules.compactMap(\.value)
        return (SpecialFoldersConfiguration(rules: rules), rules.count != stored.rules.count)
    }
}

/// SpecialFoldersConfiguration 的宽容解码形态，字段与其 Codable 结构保持一致
private struct LenientSpecialFoldersConfiguration: Decodable {
    let rules: [FailableDecodable<SpecialFolderRule>]
}
