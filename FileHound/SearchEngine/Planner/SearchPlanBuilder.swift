struct SearchPlanBuilder: Sendable {
    func build(from compiledQuery: CompiledQuery, mode: SearchMode) -> SearchPlan {
        let executableGroup = compiledQuery.rootGroup.removingExclusions() ?? .all([])
        return SearchPlan(
            rootPaths: compiledQuery.rootPaths,
            rootGroup: executableGroup,
            excludedPathFragments: compiledQuery.excludedPathFragments,
            providerKind: providerKind(for: mode),
            shouldScanContents: compiledQuery.requiresContentScan
        )
    }

    private func providerKind(for mode: SearchMode) -> ProviderKind {
        switch mode {
        case .standard:
            return .local
        case .privileged:
            return .privileged
        }
    }
}

private extension QueryGroup {
    func removingExclusions() -> QueryGroup? {
        switch self {
        case .all(let groups):
            let cleaned = groups.compactMap { $0.removingExclusions() }
            return cleaned.isEmpty ? nil : .all(cleaned)
        case .any(let groups):
            let cleaned = groups.compactMap { $0.removingExclusions() }
            return cleaned.isEmpty ? nil : .any(cleaned)
        case .exclude:
            return nil
        case .rule:
            return self
        }
    }
}
