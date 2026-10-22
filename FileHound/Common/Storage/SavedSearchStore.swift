import Foundation

enum SavedSearchCompatibilityMode: String, Codable, Sendable {
    case full
    case compiledQueryOnly
    case legacySummary
}

struct SavedSearch: Codable, Equatable, Sendable {
    var name: String
    let querySummary: String
    let createdAt: Date
    var criteria: SearchCriteriaSnapshot?
    var presentationState: ResultPresentationState?
    private var compatibilityMode: SavedSearchCompatibilityMode?

    var compatibility: SavedSearchCompatibilityMode {
        compatibilityMode ?? .legacySummary
    }

    init(
        name: String,
        querySummary: String,
        createdAt: Date,
        criteria: SearchCriteriaSnapshot? = nil,
        presentationState: ResultPresentationState? = nil,
        compatibilityMode: SavedSearchCompatibilityMode? = nil
    ) {
        self.name = name
        self.querySummary = querySummary
        self.createdAt = createdAt
        self.criteria = criteria
        self.presentationState = presentationState
        self.compatibilityMode = compatibilityMode
    }
}

final class SavedSearchStore {
    static let shared = SavedSearchStore(storage: MMKVKeyValueStore.shared)

    private let storage: KeyValueStoring
    private let key = "savedSearches"

    init(storage: KeyValueStoring = MMKVKeyValueStore.shared) {
        self.storage = storage
    }

    func save(name: String, query: SearchQuery) throws {
        let criteria = SearchCriteriaSnapshot(query: query)
        let compatibility: SavedSearchCompatibilityMode = criteria.rules.isEmpty ? .compiledQueryOnly : .full
        try save(
            SavedSearch(
                name: name,
                querySummary: criteria.querySummary,
                createdAt: Date(),
                criteria: criteria,
                presentationState: nil,
                compatibilityMode: compatibility
            )
        )
    }

    func save(
        name: String,
        criteria: SearchCriteriaSnapshot,
        presentationState: ResultPresentationState? = nil
    ) throws {
        try save(
            SavedSearch(
                name: name,
                querySummary: criteria.querySummary,
                createdAt: Date(),
                criteria: criteria,
                presentationState: presentationState,
                compatibilityMode: .full
            )
        )
    }

    func save(_ search: SavedSearch) throws {
        var searches = searchesForWriting()
        searches.append(search)
        try storage.setCodable(searches, forKey: key)
    }

    func delete(_ search: SavedSearch) throws {
        var searches = searchesForWriting()
        guard let index = index(of: search, in: searches) else {
            return
        }
        searches.remove(at: index)
        try storage.setCodable(searches, forKey: key)
    }

    func rename(_ search: SavedSearch, to newName: String) throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var searches = searchesForWriting()
        guard trimmedName.isEmpty == false, let index = index(of: search, in: searches) else {
            return
        }
        searches[index].name = trimmedName
        try storage.setCodable(searches, forKey: key)
    }

    /// 存储项没有独立 ID，按名称与创建时间定位
    private func index(of search: SavedSearch, in searches: [SavedSearch]) -> Int? {
        searches.firstIndex { $0.name == search.name && $0.createdAt == search.createdAt }
    }

    func all() -> [SavedSearch] {
        loadSearches().elements
    }

    /// 逐元素解码：完整条目按原样读取；条件无法解码（例如新版本写入的未知规则）的条目降级为仅摘要；
    /// 两种方式都无法解码的坏条目被跳过，不影响其他条目
    private func loadSearches() -> LenientDecodedArray<SavedSearch> {
        let loaded = storage.lenientArray(StoredSavedSearch.self, forKey: key)
        let isDowngraded = loaded.elements.contains { $0.isDowngraded }
        return LenientDecodedArray(
            elements: loaded.elements.map(\.search),
            isLossy: loaded.isLossy || isDowngraded
        )
    }

    /// 写回前读取：若原始数据有条目被跳过或降级，先备份原始数据，避免写回后永久丢失
    private func searchesForWriting() -> [SavedSearch] {
        let loaded = loadSearches()
        if loaded.isLossy {
            storage.backupRawValue(forKey: key)
        }
        return loaded.elements
    }
}

/// 单个已存储搜索的宽容解码：优先按完整结构解码，失败时按旧版摘要结构降级
private struct StoredSavedSearch: Decodable {
    let search: SavedSearch
    /// 完整结构解码失败、降级为仅摘要（原条件数据会在写回时丢失）
    let isDowngraded: Bool

    init(from decoder: Decoder) throws {
        if let search = try? SavedSearch(from: decoder) {
            self.search = search
            self.isDowngraded = false
            return
        }

        let legacy = try LegacySavedSearch(from: decoder)
        self.search = SavedSearch(
            name: legacy.name,
            querySummary: legacy.querySummary,
            createdAt: legacy.createdAt,
            criteria: nil,
            presentationState: nil,
            compatibilityMode: .legacySummary
        )
        self.isDowngraded = true
    }
}

private struct LegacySavedSearch: Codable {
    let name: String
    let querySummary: String
    let createdAt: Date
}
