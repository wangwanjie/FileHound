struct SearchPlanBuilder: Sendable {
    func build(from compiledQuery: CompiledQuery, mode: SearchMode) -> SearchPlan {
        SearchPlan(
            rootPaths: compiledQuery.rootPaths,
            rootGroup: compiledQuery.rootGroup,
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
