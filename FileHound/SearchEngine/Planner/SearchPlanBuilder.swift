import Foundation

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

struct SpecialFolderPlanningResult: Equatable, Sendable {
    let includedPathRoots: Set<String>
    let specialFolderExclusions: Set<String>
    let slowSearchPaths: Set<String>

    init(
        includedPathRoots: Set<String> = [],
        specialFolderExclusions: Set<String> = [],
        slowSearchPaths: Set<String> = []
    ) {
        self.includedPathRoots = includedPathRoots
        self.specialFolderExclusions = specialFolderExclusions
        self.slowSearchPaths = slowSearchPaths
    }

    func allows(path: String) -> Bool {
        let normalizedPath = Self.normalized(path)
        let isExcluded = specialFolderExclusions.contains {
            Self.isSameOrDescendant(normalizedPath, of: $0)
        }

        guard isExcluded else {
            return true
        }

        return includedPathRoots.contains {
            Self.isSameOrDescendant($0, of: normalizedPath) ||
            Self.isSameOrDescendant(normalizedPath, of: $0)
        }
    }

    fileprivate static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    fileprivate static func isSameOrDescendant(_ path: String, of ancestor: String) -> Bool {
        path == ancestor || path.hasPrefix(ancestor.hasSuffix("/") ? ancestor : ancestor + "/")
    }
}

struct SpecialFolderPlanner: Sendable {
    func plan(rootPath: String, configuration: SpecialFoldersConfiguration) -> SpecialFolderPlanningResult {
        let normalizedRoot = SpecialFolderPlanningResult.normalized(rootPath)
        var includedPathRoots: Set<String> = []
        var specialFolderExclusions: Set<String> = []
        var slowSearchPaths: Set<String> = []

        for rule in configuration.rules {
            let normalizedRulePath = SpecialFolderPlanningResult.normalized(rule.path)
            guard isRelevant(rulePath: normalizedRulePath, to: normalizedRoot) else {
                continue
            }

            switch rule.disposition {
            case .include:
                includedPathRoots.insert(normalizedRulePath)
            case .exclude:
                guard explicitlyTargets(rulePath: normalizedRulePath, rootPath: normalizedRoot) == false else {
                    continue
                }
                specialFolderExclusions.insert(normalizedRulePath)
            case .slowSearch:
                slowSearchPaths.insert(normalizedRulePath)
            }
        }

        return SpecialFolderPlanningResult(
            includedPathRoots: includedPathRoots,
            specialFolderExclusions: specialFolderExclusions,
            slowSearchPaths: slowSearchPaths
        )
    }

    private func isRelevant(rulePath: String, to rootPath: String) -> Bool {
        SpecialFolderPlanningResult.isSameOrDescendant(rulePath, of: rootPath) ||
        SpecialFolderPlanningResult.isSameOrDescendant(rootPath, of: rulePath)
    }

    private func explicitlyTargets(rulePath: String, rootPath: String) -> Bool {
        SpecialFolderPlanningResult.isSameOrDescendant(rootPath, of: rulePath)
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
