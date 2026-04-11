enum SearchScope: Codable, Equatable, Sendable {
    case roots([String])

    var rootPaths: [String] {
        switch self {
        case .roots(let paths):
            return paths
        }
    }
}

enum QueryRule: Codable, Equatable, Sendable {
    case nameContains(String)
    case pathContains(String)
    case extensionIs(String)
    case contentContains(String)
    case nameMatchesRegex(String)
    case contentMatchesRegex(String)
}

indirect enum QueryGroup: Codable, Equatable, Sendable {
    case all([QueryGroup])
    case any([QueryGroup])
    case exclude(QueryRule)
    case rule(QueryRule)
}
