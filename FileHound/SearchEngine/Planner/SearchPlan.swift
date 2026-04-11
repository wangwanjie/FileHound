import Foundation

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
    let includedPathRoots: Set<String>
    let specialFolderExclusions: Set<String>
    let slowSearchPaths: Set<String>

    init(
        rootPaths: [String],
        rootGroup: QueryGroup,
        excludedPathFragments: Set<String>,
        providerKind: ProviderKind,
        shouldScanContents: Bool,
        includedPathRoots: Set<String> = [],
        specialFolderExclusions: Set<String> = [],
        slowSearchPaths: Set<String> = []
    ) {
        self.rootPaths = rootPaths
        self.rootGroup = rootGroup
        self.excludedPathFragments = excludedPathFragments
        self.providerKind = providerKind
        self.shouldScanContents = shouldScanContents
        self.includedPathRoots = includedPathRoots
        self.specialFolderExclusions = specialFolderExclusions
        self.slowSearchPaths = slowSearchPaths
    }

    var specialFolderPlanningResult: SpecialFolderPlanningResult {
        SpecialFolderPlanningResult(
            includedPathRoots: includedPathRoots,
            specialFolderExclusions: specialFolderExclusions,
            slowSearchPaths: slowSearchPaths
        )
    }
}
