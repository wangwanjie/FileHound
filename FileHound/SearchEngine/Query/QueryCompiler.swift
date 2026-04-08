struct CompiledQuery: Sendable {
    let rootPaths: [String]
    let requiresContentScan: Bool
    let excludedPathFragments: Set<String>
}

struct QueryCompiler {
    func compile(_ query: SearchQuery) throws -> CompiledQuery {
        var excluded: Set<String> = []
        let requiresContent = query.rootGroup.containsContentRule
        query.rootGroup.collectExcludedPathFragments(into: &excluded)
        return CompiledQuery(
            rootPaths: query.scope.rootPaths,
            requiresContentScan: requiresContent,
            excludedPathFragments: excluded
        )
    }
}

private extension QueryGroup {
    var containsContentRule: Bool {
        switch self {
        case .all(let groups), .any(let groups):
            return groups.contains(where: \.containsContentRule)
        case .exclude(let rule), .rule(let rule):
            switch rule {
            case .contentContains, .contentMatchesRegex:
                return true
            default:
                return false
            }
        }
    }

    func collectExcludedPathFragments(into set: inout Set<String>) {
        switch self {
        case .all(let groups), .any(let groups):
            groups.forEach { $0.collectExcludedPathFragments(into: &set) }
        case .exclude(let rule):
            if case .pathContains(let fragment) = rule {
                set.insert(fragment)
            }
        case .rule:
            break
        }
    }
}
