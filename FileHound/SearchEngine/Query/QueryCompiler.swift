struct CompiledQuery: Sendable {
    let rootPaths: [String]
    let rootGroup: QueryGroup
    let requiresContentScan: Bool
    let excludedPathFragments: Set<String>
}

enum QueryCompilerError: Error, Equatable, Sendable {
    case unsupportedExclusion(QueryRule)
}

struct QueryCompiler {
    func compile(_ query: SearchQuery) throws -> CompiledQuery {
        var excluded: Set<String> = []
        let requiresContent = query.rootGroup.containsContentRule
        try query.rootGroup.collectExcludedPathFragments(into: &excluded)
        return CompiledQuery(
            rootPaths: query.scope.rootPaths,
            rootGroup: query.rootGroup,
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

    func collectExcludedPathFragments(into set: inout Set<String>) throws {
        switch self {
        case .all(let groups), .any(let groups):
            for group in groups {
                try group.collectExcludedPathFragments(into: &set)
            }
        case .exclude(let rule):
            if case .pathContains(let fragment) = rule {
                set.insert(fragment)
            } else {
                throw QueryCompilerError.unsupportedExclusion(rule)
            }
        case .rule:
            break
        }
    }
}
