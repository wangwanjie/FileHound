enum SearchMode: Equatable, Sendable {
    case standard
    case privileged
}

enum ProviderKind: Equatable, Sendable {
    case local
    case privileged
}

struct SearchPlan: Equatable, Sendable {
    let rootPaths: [String]
    let rootGroup: QueryGroup
    let excludedPathFragments: Set<String>
    let providerKind: ProviderKind
    let shouldScanContents: Bool
}
