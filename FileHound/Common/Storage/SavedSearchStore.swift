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
        var searches = all()
        searches.append(search)
        try storage.setCodable(searches, forKey: key)
    }

    func delete(_ search: SavedSearch) throws {
        var searches = all()
        guard let index = index(of: search, in: searches) else {
            return
        }
        searches.remove(at: index)
        try storage.setCodable(searches, forKey: key)
    }

    func rename(_ search: SavedSearch, to newName: String) throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var searches = all()
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
        if let searches = try? storage.codableValue([SavedSearch].self, forKey: key) {
            return searches
        }

        if let legacy = try? storage.codableValue([LegacySavedSearch].self, forKey: key) {
            return legacy.map {
                SavedSearch(
                    name: $0.name,
                    querySummary: $0.querySummary,
                    createdAt: $0.createdAt,
                    criteria: nil,
                    presentationState: nil,
                    compatibilityMode: .legacySummary
                )
            }
        }

        return []
    }
}

private struct LegacySavedSearch: Codable {
    let name: String
    let querySummary: String
    let createdAt: Date
}
