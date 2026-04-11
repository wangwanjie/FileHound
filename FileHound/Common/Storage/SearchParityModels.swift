import Foundation

enum SearchActivationMode: String, CaseIterable, Codable, Sendable {
    case finderOnly
    case global
}

enum SearchScopeSourceKind: String, Codable, Sendable {
    case preset
    case mountedVolume
    case folder
    case recentLocation
}

struct SearchScopeSnapshot: Codable, Equatable, Sendable {
    var title: String
    var representedPath: String?
    var scopeDescription: String
    var sourceKind: SearchScopeSourceKind

    var rootPath: String {
        representedPath ?? "/"
    }

    init(
        title: String,
        representedPath: String?,
        scopeDescription: String,
        sourceKind: SearchScopeSourceKind
    ) {
        self.title = title
        self.representedPath = representedPath
        self.scopeDescription = scopeDescription
        self.sourceKind = sourceKind
    }
}

struct SearchCriteriaSnapshot: Codable, Equatable, Sendable {
    var scope: SearchScopeSnapshot
    var rules: [SearchRuleSelection]
    var compiledQuery: SearchQuery?

    init(
        scope: SearchScopeSnapshot,
        rules: [SearchRuleSelection],
        compiledQuery: SearchQuery? = nil
    ) {
        self.scope = scope
        self.rules = rules
        self.compiledQuery = compiledQuery
    }

    init(query: SearchQuery) {
        let rootPath = query.scope.rootPaths.first ?? "/"
        let scopeTitle: String
        let scopeDescription: String

        if rootPath == "/" {
            scopeTitle = "on startup volume"
            scopeDescription = "Macintosh HD"
        } else {
            let url = URL(fileURLWithPath: rootPath)
            scopeTitle = "inside \(url.lastPathComponent)"
            scopeDescription = url.lastPathComponent
        }

        self.scope = SearchScopeSnapshot(
            title: scopeTitle,
            representedPath: rootPath,
            scopeDescription: scopeDescription,
            sourceKind: rootPath == "/" ? .preset : .folder
        )
        self.rules = SearchRuleSelection.translated(from: query.rootGroup)
        self.compiledQuery = query
    }

    var querySummary: String {
        if rules.isEmpty == false {
            return rules
                .map(\.summaryText)
                .joined(separator: L10n.string("search_rule.summary.and_separator"))
        }

        return compiledQuery?.summaryText ?? scope.scopeDescription
    }
}

enum ResultViewMode: String, Codable, Sendable {
    case grid
    case table
    case tree
}

enum ResultSortField: String, Codable, Sendable {
    case name
    case dateModified
    case dateCreated
    case lastOpened
    case dateAdded
    case kind
    case size
    case tags
    case enclosingFolder
    case path
}

enum ResultSortOrder: String, Codable, Sendable {
    case ascending
    case descending
}

struct ResultPresentationState: Codable, Equatable, Sendable {
    var mode: ResultViewMode
    var sortField: ResultSortField
    var sortOrder: ResultSortOrder
    var filterText: String
    var showInvisibleItems: Bool
    var showPackageContents: Bool
    var showTrashedItems: Bool
    var previewSize: Double

    init(
        mode: ResultViewMode = .grid,
        sortField: ResultSortField = .name,
        sortOrder: ResultSortOrder = .ascending,
        filterText: String = "",
        showInvisibleItems: Bool = false,
        showPackageContents: Bool = false,
        showTrashedItems: Bool = false,
        previewSize: Double = 72
    ) {
        self.mode = mode
        self.sortField = sortField
        self.sortOrder = sortOrder
        self.filterText = filterText
        self.showInvisibleItems = showInvisibleItems
        self.showPackageContents = showPackageContents
        self.showTrashedItems = showTrashedItems
        self.previewSize = previewSize
    }
}

enum SpecialFolderDisposition: String, Codable, Sendable {
    case include
    case exclude
    case slowSearch
}

struct SpecialFolderRule: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var path: String
    var disposition: SpecialFolderDisposition

    init(
        id: UUID = UUID(),
        path: String,
        disposition: SpecialFolderDisposition
    ) {
        self.id = id
        self.path = path
        self.disposition = disposition
    }
}

struct SpecialFoldersConfiguration: Codable, Equatable, Sendable {
    var rules: [SpecialFolderRule]

    init(rules: [SpecialFolderRule] = []) {
        self.rules = rules
    }

    static let empty = SpecialFoldersConfiguration()
}

struct RecentLocationRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var scope: SearchScopeSnapshot
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        scope: SearchScopeSnapshot,
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.lastUsedAt = lastUsedAt
    }
}

struct RecentSearchRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var criteria: SearchCriteriaSnapshot
    var presentationState: ResultPresentationState?
    var executedAt: Date
    var resultCount: Int?

    init(
        id: UUID = UUID(),
        title: String,
        criteria: SearchCriteriaSnapshot,
        presentationState: ResultPresentationState? = nil,
        executedAt: Date = Date(),
        resultCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.criteria = criteria
        self.presentationState = presentationState
        self.executedAt = executedAt
        self.resultCount = resultCount
    }
}

struct SearchSessionSnapshot: Codable, Equatable, Sendable {
    var criteria: SearchCriteriaSnapshot
    var presentationState: ResultPresentationState?
    var savedAt: Date

    init(
        criteria: SearchCriteriaSnapshot,
        presentationState: ResultPresentationState? = nil,
        savedAt: Date = Date()
    ) {
        self.criteria = criteria
        self.presentationState = presentationState
        self.savedAt = savedAt
    }
}

struct GeneralSearchPreferences: Codable, Equatable, Sendable {
    var launchShortcut: String
    var activationMode: SearchActivationMode
    var openRecentSearchMenu: Bool
    var restorePreviousSearch: Bool
    var tieResultsWindowToFindWindow: Bool
    var quitWhenAllWindowsAreClosed: Bool

    init(
        launchShortcut: String = "",
        activationMode: SearchActivationMode = .global,
        openRecentSearchMenu: Bool = true,
        restorePreviousSearch: Bool = false,
        tieResultsWindowToFindWindow: Bool = true,
        quitWhenAllWindowsAreClosed: Bool = true
    ) {
        self.launchShortcut = launchShortcut
        self.activationMode = activationMode
        self.openRecentSearchMenu = openRecentSearchMenu
        self.restorePreviousSearch = restorePreviousSearch
        self.tieResultsWindowToFindWindow = tieResultsWindowToFindWindow
        self.quitWhenAllWindowsAreClosed = quitWhenAllWindowsAreClosed
    }
}

struct SearchExecutionPreferences: Codable, Equatable, Sendable {
    var expandFoldersWhenShowingResults: Bool
    var showResultsEarly: Bool
    var includeSpotlightResults: Bool

    init(
        expandFoldersWhenShowingResults: Bool = false,
        showResultsEarly: Bool = true,
        includeSpotlightResults: Bool = true
    ) {
        self.expandFoldersWhenShowingResults = expandFoldersWhenShowingResults
        self.showResultsEarly = showResultsEarly
        self.includeSpotlightResults = includeSpotlightResults
    }
}

struct AppearancePreferences: Codable, Equatable, Sendable {
    var preferredTheme: AppTheme
    var preferredLanguage: AppLanguage
    var resultsFontSize: Int
    var dimColorHex: String

    init(
        preferredTheme: AppTheme = .system,
        preferredLanguage: AppLanguage = .system,
        resultsFontSize: Int = 13,
        dimColorHex: String = "#A0A7B3"
    ) {
        self.preferredTheme = preferredTheme
        self.preferredLanguage = preferredLanguage
        self.resultsFontSize = resultsFontSize
        self.dimColorHex = dimColorHex
    }
}

struct UpdatePreferences: Codable, Equatable, Sendable {
    var updateCheckPolicy: UpdateCheckPolicy
    var autoDownloadUpdates: Bool

    init(
        updateCheckPolicy: UpdateCheckPolicy = .onLaunch,
        autoDownloadUpdates: Bool = false
    ) {
        self.updateCheckPolicy = updateCheckPolicy
        self.autoDownloadUpdates = autoDownloadUpdates
    }
}

extension SearchRuleSelection {
    static func translated(from group: QueryGroup) -> [SearchRuleSelection] {
        switch group {
        case .all(let groups), .any(let groups):
            return groups.flatMap(translated(from:))
        case .rule(let rule):
            return translated(rule: rule, isExcluded: false)
        case .exclude(let rule):
            return translated(rule: rule, isExcluded: true)
        }
    }

    private static func translated(rule: QueryRule, isExcluded: Bool) -> [SearchRuleSelection] {
        let selection: SearchRuleSelection?

        switch rule {
        case .nameContains(let value):
            selection = SearchRuleSelection(field: .name, operator: isExcluded ? .doesNotContain : .contains, value: value)
        case .pathContains(let value):
            selection = SearchRuleSelection(field: .path, operator: isExcluded ? .doesNotContain : .contains, value: value)
        case .extensionIs(let value):
            selection = SearchRuleSelection(field: .extensionName, operator: isExcluded ? .doesNotContain : .isExactly, value: value)
        case .contentContains(let value):
            selection = SearchRuleSelection(field: .textContent, operator: isExcluded ? .doesNotContain : .contains, value: value)
        case .nameMatchesRegex(let value):
            selection = SearchRuleSelection(field: .name, operator: isExcluded ? .doesNotMatchRegex : .matchesRegex, value: value)
        case .contentMatchesRegex(let value):
            selection = SearchRuleSelection(field: .textContent, operator: isExcluded ? .doesNotMatchRegex : .matchesRegex, value: value)
        }

        return selection.map { [$0] } ?? []
    }
}

extension SearchQuery {
    var summaryText: String {
        rootGroup.summaryText
    }
}

private extension QueryGroup {
    var summaryText: String {
        switch self {
        case .all(let groups):
            return groups.map(\.summaryText).joined(separator: L10n.string("search_rule.summary.and_separator"))
        case .any(let groups):
            return groups.map(\.summaryText).joined(separator: L10n.string("search_rule.summary.or_separator"))
        case .exclude(let rule):
            return L10n.format("search_rule.summary.not", rule.summaryText)
        case .rule(let rule):
            return rule.summaryText
        }
    }
}

private extension QueryRule {
    var summaryText: String {
        switch self {
        case .nameContains(let value):
            return L10n.format("search_rule.summary.query.name_contains", value)
        case .pathContains(let value):
            return L10n.format("search_rule.summary.query.path_contains", value)
        case .extensionIs(let value):
            return L10n.format("search_rule.summary.query.extension_is", value)
        case .contentContains(let value):
            return L10n.format("search_rule.summary.query.content_contains", value)
        case .nameMatchesRegex(let value):
            return L10n.format("search_rule.summary.query.name_matches_regex", value)
        case .contentMatchesRegex(let value):
            return L10n.format("search_rule.summary.query.content_matches_regex", value)
        }
    }
}
