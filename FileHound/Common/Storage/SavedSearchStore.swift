import Foundation

struct SavedSearch: Codable, Equatable, Sendable {
    let name: String
    let querySummary: String
    let createdAt: Date
}

final class SavedSearchStore {
    private let storage: KeyValueStoring
    private let key = "savedSearches"

    init(storage: KeyValueStoring = InMemoryKeyValueStore()) {
        self.storage = storage
    }

    func save(name: String, query: SearchQuery) throws {
        var searches = all()
        searches.append(
            SavedSearch(
                name: name,
                querySummary: query.scope.rootPaths.joined(separator: ","),
                createdAt: Date()
            )
        )
        try storage.setCodable(searches, forKey: key)
    }

    func all() -> [SavedSearch] {
        (try? storage.codableValue([SavedSearch].self, forKey: key)) ?? []
    }
}
