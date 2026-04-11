struct SearchQuery: Codable, Equatable, Sendable {
    var scope: SearchScope
    var rootGroup: QueryGroup
}
