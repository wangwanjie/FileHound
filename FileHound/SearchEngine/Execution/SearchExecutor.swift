import Foundation
import UniformTypeIdentifiers

struct SearchExecutionOptions: Sendable {
    var includeSpotlightResults: Bool = true
}

struct SearchExecutionResult: Sendable {
    let title: String
    let items: [SearchResultItem]
}

struct SearchExecutionProgress: Sendable {
    let title: String
    let items: [SearchResultItem]
    let matchedCount: Int
}

struct SearchExecutor: Sendable {
    private let walker: DirectoryWalker
    private let provider: any FilesystemAccessProviding
    private let spotlightSearchService: SpotlightSearchService
    private let specialFoldersStore: SpecialFoldersStore
    private let specialFolderPlanner: SpecialFolderPlanner
    private let fileKindResolver: FileKindResolver
    private let nowProvider: @Sendable () -> Date
    private let metadataEvaluator = MetadataEvaluator()
    private let contentMatcher = ContentMatcher()

    init(
        walker: DirectoryWalker = DirectoryWalker(),
        provider: any FilesystemAccessProviding = LocalFilesystemProvider(),
        spotlightSearchService: SpotlightSearchService = SpotlightSearchService(),
        specialFoldersStore: SpecialFoldersStore = .shared,
        specialFolderPlanner: SpecialFolderPlanner = SpecialFolderPlanner(),
        fileKindResolver: FileKindResolver = FileKindResolver(),
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.walker = walker
        self.provider = provider
        self.spotlightSearchService = spotlightSearchService
        self.specialFoldersStore = specialFoldersStore
        self.specialFolderPlanner = specialFolderPlanner
        self.fileKindResolver = fileKindResolver
        self.nowProvider = nowProvider
    }

    func execute(
        request: SearchRequest,
        options: SearchExecutionOptions = SearchExecutionOptions()
    ) -> SearchExecutionResult {
        executeStreaming(request: request, options: options)
    }

    func executeStreaming(
        request: SearchRequest,
        options: SearchExecutionOptions = SearchExecutionOptions(),
        onProgress: (@Sendable (SearchExecutionProgress) -> Void)? = nil
    ) -> SearchExecutionResult {
        let title = request.queryTitle
        let specialFolderPlanning = mergedSpecialFolderPlanning(for: request.rootPaths)
        let behavior = SearchRuleExecutionBehavior(rules: request.rules)
        let highlight = highlightMetadata(for: request.rules)
        let plan = SearchPlan(
            rootPaths: request.rootPaths,
            rootGroup: .all([]),
            excludedPathFragments: [],
            providerKind: .local,
            shouldScanContents: request.rules.contains(where: { $0.field == .textContent }),
            includedPathRoots: specialFolderPlanning.includedPathRoots,
            specialFolderExclusions: specialFolderPlanning.specialFolderExclusions,
            slowSearchPaths: specialFolderPlanning.slowSearchPaths
        )
        var items: [SearchResultItem] = []
        var seenPaths = Set<String>()
        let prefersSpotlightTextResults = options.includeSpotlightResults && spotlightSearchService.canSatisfyTextContentSearch(
            rules: request.rules,
            caseSensitive: behavior.caseSensitive,
            diacriticsSensitive: behavior.diacriticsSensitive
        )

        func appendResult(_ item: SearchResultItem) -> Bool {
            guard seenPaths.insert(item.path).inserted else {
                return false
            }

            items.append(item)
            onProgress?(.init(title: title, items: items, matchedCount: items.count))
            return true
        }

        if options.includeSpotlightResults,
           let spotlightItems = executeSpotlightSearchIfPossible(
                request: request,
                specialFolderPlanning: specialFolderPlanning,
                behavior: behavior,
                highlight: highlight
           ) {
            for item in spotlightItems where behavior.allows(item: item) {
                _ = appendResult(item)
                if behavior.hasReachedLimit(items.count) {
                    return SearchExecutionResult(title: title, items: items)
                }
            }

            if prefersSpotlightTextResults, items.isEmpty == false {
                return SearchExecutionResult(title: title, items: items)
            }
        }

        do {
            _ = try walker.walk(plan: plan, includeHiddenFiles: behavior.includeInvisibleItems) { entry in
                if seenPaths.contains(entry.path) {
                    return behavior.hasReachedLimit(items.count) ? .stop : .continue
                }

                guard Self.isExcluded(entry.path, by: request.excludedPaths) == false else {
                    return .skipDescendants
                }

                let rootPath = Self.rootPath(containing: entry.path, in: request.rootPaths)
                let descendControl: DirectoryWalkControl =
                    behavior.shouldDescend(into: entry, rootPath: rootPath) ? .continue : .skipDescendants

                guard behavior.allows(entry: entry, rootPath: rootPath) else {
                    return descendControl
                }

                do {
                    let attributes = try provider.attributesOfItem(atPath: entry.path)
                    guard try request.rules.allSatisfy({
                        try matches(entry: entry, attributes: attributes, rule: $0, behavior: behavior)
                    }) else {
                        return descendControl
                    }

                    let item = try makeResultItem(
                        for: entry,
                        attributes: attributes,
                        preview: request.rules.first?.value ?? "",
                        highlight: highlight
                    )
                    guard behavior.allows(item: item) else {
                        return descendControl
                    }
                    _ = appendResult(item)
                    return behavior.hasReachedLimit(items.count) ? .stop : descendControl
                } catch {
                    return descendControl
                }
            }

            return SearchExecutionResult(title: title, items: items)
        } catch {
            return SearchExecutionResult(title: title, items: [])
        }
    }

    private func executeSpotlightSearchIfPossible(
        request: SearchRequest,
        specialFolderPlanning: SpecialFolderPlanningResult,
        behavior: SearchRuleExecutionBehavior,
        highlight: (kind: SearchResultHighlightKind, query: String)?
    ) -> [SearchResultItem]? {
        var paths: [String] = []
        for rootPath in request.rootPaths {
            guard let rootPaths = try? spotlightSearchService.search(rootPath: rootPath, rules: request.rules) else {
                return nil
            }
            paths += rootPaths
        }

        let uniquePaths = Array(Set(paths)).sorted()
        guard Task.isCancelled == false else {
            return nil
        }
        let preview = request.rules.first?.value ?? ""

        return uniquePaths.compactMap { path in
            guard specialFolderPlanning.allows(path: path),
                  Self.isExcluded(path, by: request.excludedPaths) == false else {
                return nil
            }

            guard FileManager.default.fileExists(atPath: path) else {
                return nil
            }

            let isDirectory = (try? provider.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeDirectory
            let entry = DirectoryEntry(
                path: path,
                isDirectory: isDirectory,
                isHidden: URL(fileURLWithPath: path).lastPathComponent.hasPrefix(".")
            )

            guard behavior.allows(entry: entry, rootPath: Self.rootPath(containing: path, in: request.rootPaths)) else {
                return nil
            }

            do {
                let attributes = try provider.attributesOfItem(atPath: path)
                // Spotlight 查询是不区分大小写的近似结果，这里按完整规则复核；
                // 文本内容由 Spotlight 索引判定（可覆盖 PDF 等非纯文本格式），不再重复读取文件
                guard try request.rules.allSatisfy({ rule in
                    if rule.field == .textContent { return true }
                    return try matches(entry: entry, attributes: attributes, rule: rule, behavior: behavior)
                }) else {
                    return nil
                }
                return try makeResultItem(for: entry, attributes: attributes, preview: preview, highlight: highlight)
            } catch {
                return nil
            }
        }
    }

    private func mergedSpecialFolderPlanning(for rootPaths: [String]) -> SpecialFolderPlanningResult {
        let configuration = specialFoldersStore.load()
        let plans = rootPaths.map { specialFolderPlanner.plan(rootPath: $0, configuration: configuration) }
        return SpecialFolderPlanningResult(
            includedPathRoots: plans.reduce(into: Set<String>()) { $0.formUnion($1.includedPathRoots) },
            specialFolderExclusions: plans.reduce(into: Set<String>()) { $0.formUnion($1.specialFolderExclusions) },
            slowSearchPaths: plans.reduce(into: Set<String>()) { $0.formUnion($1.slowSearchPaths) }
        )
    }

    /// 多根搜索时，条目的深度、包内容判断都相对于包含它的最深根目录
    static func rootPath(containing path: String, in rootPaths: [String]) -> String {
        rootPaths
            .filter { isSameOrDescendant(path, of: $0) }
            .max { $0.count < $1.count } ?? rootPaths.first ?? "/"
    }

    static func isExcluded(_ path: String, by excludedPaths: [String]) -> Bool {
        excludedPaths.contains { isSameOrDescendant(path, of: $0) }
    }

    private static func isSameOrDescendant(_ path: String, of ancestor: String) -> Bool {
        path == ancestor || path.hasPrefix(ancestor.hasSuffix("/") ? ancestor : ancestor + "/")
    }

    private func matches(
        entry: DirectoryEntry,
        attributes: [FileAttributeKey: Any],
        rule: SearchRuleSelection,
        behavior: SearchRuleExecutionBehavior
    ) throws -> Bool {
        let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false || SearchRuleExecutionBehavior.globalFields.contains(rule.field) else {
            return true
        }

        switch rule.field {
        case .name:
            return matchString(entry.lastPathComponent, using: rule, behavior: behavior)
        case .extensionName:
            return matchString(
                URL(fileURLWithPath: entry.path).pathExtension,
                using: normalizedExtensionRule(from: rule),
                behavior: behavior
            )
        case .nameWithoutExtension:
            let name = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
            return matchString(name, using: rule, behavior: behavior)
        case .lastModifiedDate:
            return compareDate(attributes[.modificationDate] as? Date, using: rule)
        case .createdDate:
            return compareDate(attributes[.creationDate] as? Date, using: rule)
        case .lastOpenedDate:
            let resourceValues = try? URL(fileURLWithPath: entry.path).resourceValues(forKeys: [.contentAccessDateKey])
            return compareDate(resourceValues?.contentAccessDate, using: rule)
        case .fileSize:
            let size = (attributes[.size] as? NSNumber)?.int64Value
            return compareNumber(size, using: rule)
        case .kind:
            return compareKind(entry: entry, attributes: attributes, using: rule)
        case .tag:
            let resourceValues = try? URL(fileURLWithPath: entry.path).resourceValues(forKeys: [.tagNamesKey])
            return matchAnyComponent(resourceValues?.tagNames ?? [], using: rule, behavior: behavior)
        case .comments:
            return false
        case .path:
            return matchString(entry.path, using: rule, behavior: behavior)
        case .folderNames:
            let folderNames = URL(fileURLWithPath: entry.path)
                .deletingLastPathComponent()
                .pathComponents
                .filter { $0 != "/" }
            return matchAnyComponent(folderNames, using: rule, behavior: behavior)
        case .textContent:
            guard entry.isDirectory == false else {
                return false
            }

            let data = try provider.contentsOfFile(atPath: entry.path)
            return try contentMatcher.matches(
                data: data,
                rule: rule,
                compareOptions: behavior.stringCompareOptions,
                caseSensitive: behavior.caseSensitive
            )
        case .script:
            return false
        case .caseSensitive, .diacriticsSensitive, .invisibleItems, .packageContents, .trashedContents, .limitFolderDepth, .limitAmount:
            return true
        }
    }

    private func makeResultItem(
        for entry: DirectoryEntry,
        attributes: [FileAttributeKey: Any],
        preview: String,
        highlight: (kind: SearchResultHighlightKind, query: String)?
    ) throws -> SearchResultItem {
        let url = URL(fileURLWithPath: entry.path)
        let resourceValues = try? url.resourceValues(forKeys: [
            .isPackageKey,
            .isHiddenKey,
            .creationDateKey,
            .contentAccessDateKey,
            .addedToDirectoryDateKey,
            .tagNamesKey
        ])
        let modifiedDate = attributes[.modificationDate] as? Date
        let createdDate = attributes[.creationDate] as? Date ?? resourceValues?.creationDate
        let lastOpenedDate = resourceValues?.contentAccessDate
        let addedDate = resourceValues?.addedToDirectoryDate
        let sizeBytes = (attributes[.size] as? NSNumber)?.int64Value
        let kind = fileKindResolver.displayTitle(for: entry.path, isDirectory: entry.isDirectory, attributes: attributes)
        return SearchResultItem(
            path: entry.path,
            matchReason: highlight.map(matchReason(for:))
                ?? L10n.string(entry.isDirectory ? "search_result.match_reason.folder" : "search_result.match_reason.name"),
            previewSnippet: preview,
            highlightKind: highlight?.kind,
            highlightQuery: highlight?.query,
            kind: kind,
            modifiedText: Self.displayDate(modifiedDate),
            createdText: Self.displayDate(createdDate),
            lastOpenedText: Self.displayDate(lastOpenedDate),
            addedText: Self.displayDate(addedDate),
            sizeText: Self.displaySize(byteCount: sizeBytes),
            tagsText: (resourceValues?.tagNames ?? []).joined(separator: ", "),
            enclosingFolder: (entry.path as NSString).deletingLastPathComponent,
            isInvisible: resourceValues?.isHidden ?? entry.isHidden,
            isPackage: resourceValues?.isPackage ?? Self.isPackagePath(entry.path),
            isTrashed: Self.isTrashedPath(entry.path),
            modifiedDate: modifiedDate,
            createdDate: createdDate,
            lastOpenedDate: lastOpenedDate,
            addedDate: addedDate,
            sizeBytes: sizeBytes,
            tags: resourceValues?.tagNames ?? []
        )
    }

    private func highlightMetadata(for rules: [SearchRuleSelection]) -> (kind: SearchResultHighlightKind, query: String)? {
        for rule in rules {
            let query = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.isEmpty == false, Self.isPositiveHighlightOperator(rule.operator) else {
                continue
            }

            switch rule.field {
            case .name:
                return (.name, query)
            case .extensionName:
                return (.extensionName, query)
            default:
                continue
            }
        }

        return nil
    }

    private func matchReason(for highlight: (kind: SearchResultHighlightKind, query: String)) -> String {
        switch highlight.kind {
        case .name:
            return L10n.string("search_result.match_reason.name")
        case .extensionName:
            return L10n.string("search_result.match_reason.extension")
        }
    }

    private func matchString(
        _ candidate: String,
        using rule: SearchRuleSelection,
        behavior: SearchRuleExecutionBehavior
    ) -> Bool {
        let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = behavior.stringCompareOptions

        switch rule.operator {
        case .contains:
            return candidate.range(of: value, options: options) != nil
        case .containsPhrase:
            return matchWholeWords(candidate, phrase: value, behavior: behavior)
        case .beginsWith:
            return candidate.range(of: value, options: options.union(.anchored)) != nil
        case .endsWith:
            return candidate.range(of: value, options: options.union(.backwards))?.upperBound == candidate.endIndex
        case .isExactly:
            return candidate.compare(value, options: options) == .orderedSame
        case .isNot:
            return candidate.compare(value, options: options) != .orderedSame
        case .doesNotContain:
            return candidate.range(of: value, options: options) == nil
        case .containsWords:
            return splitTerms(from: value).allSatisfy { matchWholeWords(candidate, phrase: $0, behavior: behavior) }
        case .matchesPattern:
            return matchRegex(candidate, pattern: wildcardPattern(from: value), caseSensitive: behavior.caseSensitive)
        case .containsAnyOf:
            return splitTerms(from: value).contains { candidate.range(of: $0, options: options) != nil }
        case .beginsWithAnyOf:
            return splitTerms(from: value).contains { candidate.range(of: $0, options: options.union(.anchored)) != nil }
        case .endsWithAnyOf:
            return splitTerms(from: value).contains {
                candidate.range(of: $0, options: options.union(.backwards))?.upperBound == candidate.endIndex
            }
        case .isAnyOf:
            return splitTerms(from: value).contains { candidate.compare($0, options: options) == .orderedSame }
        case .matchesRegex:
            return matchRegex(candidate, pattern: value, caseSensitive: behavior.caseSensitive)
        case .doesNotMatchRegex:
            return matchRegex(candidate, pattern: value, caseSensitive: behavior.caseSensitive) == false
        case .isGreaterThan, .isLessThan, .isBefore, .isAfter, .isOnOrBefore, .isOnOrAfter, .isWithinTheLast, .isToday, .isYesterday:
            return false
        }
    }

    /// 多值字段（标签、各级文件夹名）：肯定类运算符任一值命中即可，否定类运算符要求所有值都不命中
    private func matchAnyComponent(
        _ components: [String],
        using rule: SearchRuleSelection,
        behavior: SearchRuleExecutionBehavior
    ) -> Bool {
        let positiveOperator: SearchRuleOperator?
        switch rule.operator {
        case .isNot:
            positiveOperator = .isExactly
        case .doesNotContain:
            positiveOperator = .contains
        case .doesNotMatchRegex:
            positiveOperator = .matchesRegex
        default:
            positiveOperator = nil
        }

        guard let positiveOperator else {
            return components.contains { matchString($0, using: rule, behavior: behavior) }
        }

        var positiveRule = rule
        positiveRule.operator = positiveOperator
        return components.contains { matchString($0, using: positiveRule, behavior: behavior) } == false
    }

    /// 以单词边界匹配短语，避免 “port” 命中 “report”
    private func matchWholeWords(
        _ candidate: String,
        phrase: String,
        behavior: SearchRuleExecutionBehavior
    ) -> Bool {
        let foldingOptions: String.CompareOptions = behavior.diacriticsSensitive ? [] : [.diacriticInsensitive]
        let foldedCandidate = candidate.folding(options: foldingOptions, locale: nil)
        let foldedPhrase = phrase.folding(options: foldingOptions, locale: nil)
        let words = foldedPhrase.split(whereSeparator: \.isWhitespace).map {
            NSRegularExpression.escapedPattern(for: String($0))
        }
        guard words.isEmpty == false else {
            return false
        }
        let pattern = "(?<![\\p{L}\\p{N}_])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}_])"
        return matchRegex(foldedCandidate, pattern: pattern, caseSensitive: behavior.caseSensitive)
    }

    private func compareKind(
        entry: DirectoryEntry,
        attributes: [FileAttributeKey: Any],
        using rule: SearchRuleSelection
    ) -> Bool {
        let kindIDs = fileKindResolver.kindIDs(for: entry.path, isDirectory: entry.isDirectory, attributes: attributes)
        let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)

        switch rule.operator {
        case .isExactly:
            return value == "kind.any" || kindIDs.contains(value)
        case .isNot:
            guard value.isEmpty == false, value != "kind.any" else {
                return false
            }
            return kindIDs.contains(value) == false
        default:
            return false
        }
    }

    private func normalizedExtensionRule(from rule: SearchRuleSelection) -> SearchRuleSelection {
        var normalizedRule = rule
        normalizedRule.value = rule.value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalizedRule
    }

    private func splitTerms(from value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { $0.isEmpty == false }
    }

    private func wildcardPattern(from value: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: value)
        return "^" + escaped
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
    }

    private func matchRegex(_ candidate: String, pattern: String, caseSensitive: Bool) -> Bool {
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return false
        }

        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        return regex.firstMatch(in: candidate, options: [], range: range) != nil
    }

    private func compareNumber(_ candidate: Int64?, using rule: SearchRuleSelection) -> Bool {
        guard let candidate, let target = parseNumber(from: rule.value) else {
            return false
        }

        switch rule.operator {
        case .isExactly:
            return candidate == target
        case .isGreaterThan:
            return candidate > target
        case .isLessThan:
            return candidate < target
        default:
            return false
        }
    }

    private func compareDate(_ candidate: Date?, using rule: SearchRuleSelection) -> Bool {
        guard let candidate else {
            return false
        }

        let calendar = Calendar(identifier: .gregorian)
        switch rule.operator {
        case .isExactly:
            guard let target = parseDate(from: rule.value) else {
                return false
            }
            return calendar.isDate(candidate, inSameDayAs: target)
        case .isBefore:
            guard let target = parseDate(from: rule.value) else {
                return false
            }
            return candidate < calendar.startOfDay(for: target)
        case .isAfter:
            guard let target = parseDate(from: rule.value) else {
                return false
            }
            let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: target)) ?? target
            return candidate > endOfDay
        case .isOnOrAfter:
            guard let target = parseDate(from: rule.value) else {
                return false
            }
            return candidate >= calendar.startOfDay(for: target)
        case .isOnOrBefore:
            guard let target = parseDate(from: rule.value) else {
                return false
            }
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: target)) ?? target
            return candidate < endOfDay
        case .isWithinTheLast:
            guard let relative = parseRelativeDate(from: rule.value),
                  let cutoff = calendar.date(byAdding: relative.component, value: -relative.amount, to: nowProvider()) else {
                return false
            }
            return candidate >= cutoff
        case .isToday:
            return calendar.isDateInToday(candidate)
        case .isYesterday:
            return calendar.isDateInYesterday(candidate)
        default:
            return false
        }
    }

    private func parseNumber(from value: String) -> Int64? {
        SearchRuleNumberParser.parseByteCount(value)
    }

    private func parseDate(from value: String) -> Date? {
        SearchRuleDateParser.parse(value)
    }

    private func parseRelativeDate(from value: String) -> (amount: Int, component: Calendar.Component)? {
        let relative = SearchRuleRelativeDateValue.parse(value)
        guard let amount = relative.positiveAmount, let unit = relative.unit else {
            return nil
        }

        switch unit {
        case .day:
            return (amount, .day)
        case .week:
            return (amount, .weekOfYear)
        case .month:
            return (amount, .month)
        }
    }

    private static func displayDate(_ date: Date?) -> String {
        guard let date else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func displaySize(byteCount: Int64?) -> String {
        guard let byteCount else {
            return ""
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    private static func isPackagePath(_ path: String) -> Bool {
        let packageExtensions: Set<String> = ["app", "bundle", "framework", "plugin", "xcodeproj", "playground"]
        return packageExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    fileprivate static func isTrashedPath(_ path: String) -> Bool {
        path.contains("/.Trash/") || path.contains("/.Trashes/")
    }

    private static func isPositiveHighlightOperator(_ searchOperator: SearchRuleOperator) -> Bool {
        switch searchOperator {
        case .contains, .containsPhrase, .beginsWith, .endsWith, .isExactly, .containsWords, .containsAnyOf, .beginsWithAnyOf, .endsWithAnyOf, .isAnyOf:
            return true
        default:
            return false
        }
    }
}

private struct SearchRuleExecutionBehavior {
    static let globalFields: Set<SearchRuleField> = [
        .caseSensitive,
        .diacriticsSensitive,
        .invisibleItems,
        .packageContents,
        .trashedContents,
        .limitFolderDepth,
        .limitAmount
    ]

    let caseSensitive: Bool
    let diacriticsSensitive: Bool
    let includeInvisibleItems: Bool
    let includePackageContents: Bool
    let includeTrashedContents: Bool
    /// 允许的最大相对深度（含），nil 表示不限
    let maximumFolderDepth: Int?
    /// 允许的最小相对深度（含），用于“深度大于 N”
    let minimumFolderDepth: Int?
    let limitAmount: Int?

    init(rules: [SearchRuleSelection]) {
        caseSensitive = Self.booleanValue(for: .caseSensitive, in: rules) ?? false
        diacriticsSensitive = Self.booleanValue(for: .diacriticsSensitive, in: rules) ?? false
        includeInvisibleItems = Self.booleanValue(for: .invisibleItems, in: rules) ?? true
        includePackageContents = Self.booleanValue(for: .packageContents, in: rules) ?? true
        includeTrashedContents = Self.booleanValue(for: .trashedContents, in: rules) ?? true
        let depthRule = Self.intRule(for: .limitFolderDepth, in: rules)
        switch depthRule?.operator {
        case .isGreaterThan:
            maximumFolderDepth = nil
            minimumFolderDepth = depthRule.map { $0.value + 1 }
        case .isLessThan:
            maximumFolderDepth = depthRule.map { max($0.value - 1, 0) }
            minimumFolderDepth = nil
        default:
            maximumFolderDepth = depthRule?.value
            minimumFolderDepth = nil
        }

        let amountRule = Self.intRule(for: .limitAmount, in: rules)
        switch amountRule?.operator {
        case .isLessThan:
            limitAmount = amountRule.map { max($0.value - 1, 0) }
        default:
            limitAmount = amountRule?.value
        }
    }

    var stringCompareOptions: String.CompareOptions {
        var options: String.CompareOptions = []
        if caseSensitive == false {
            options.insert(.caseInsensitive)
        }
        if diacriticsSensitive == false {
            options.insert(.diacriticInsensitive)
        }
        return options
    }

    func allows(entry: DirectoryEntry, rootPath: String) -> Bool {
        if includeInvisibleItems == false, entry.isHidden {
            return false
        }

        if includePackageContents == false, SearchExecutor.isInsidePackageContents(entry.path, relativeTo: rootPath) {
            return false
        }

        if includeTrashedContents == false, SearchExecutor.isTrashedPath(entry.path) {
            return false
        }

        let depth = relativeDepth(of: entry.path, rootPath: rootPath)
        if let maximumFolderDepth, depth > maximumFolderDepth {
            return false
        }
        if let minimumFolderDepth, depth < minimumFolderDepth {
            return false
        }

        return true
    }

    /// 遍历时是否需要进入该目录：超出深度、被排除的包或废纸篓不再展开
    func shouldDescend(into entry: DirectoryEntry, rootPath: String) -> Bool {
        guard entry.isDirectory else {
            return false
        }
        if let maximumFolderDepth, relativeDepth(of: entry.path, rootPath: rootPath) >= maximumFolderDepth {
            return false
        }
        if includePackageContents == false,
           SearchExecutor.isInsidePackageContents(entry.path + "/_", relativeTo: rootPath) {
            return false
        }
        if includeTrashedContents == false, SearchExecutor.isTrashedPath(entry.path + "/") {
            return false
        }
        return true
    }

    func allows(item: SearchResultItem) -> Bool {
        if includeInvisibleItems == false, item.isInvisible {
            return false
        }
        if includePackageContents == false, SearchExecutor.isInsidePackageContents(item.path) {
            return false
        }
        if includeTrashedContents == false, item.isTrashed {
            return false
        }
        return true
    }

    func hasReachedLimit(_ count: Int) -> Bool {
        guard let limitAmount, limitAmount > 0 else {
            return false
        }
        return count >= limitAmount
    }

    private func relativeDepth(of path: String, rootPath: String) -> Int {
        let pathComponents = URL(fileURLWithPath: path).pathComponents
        let rootComponents = URL(fileURLWithPath: rootPath).pathComponents
        return max(pathComponents.count - rootComponents.count, 0)
    }

    private static func booleanValue(for field: SearchRuleField, in rules: [SearchRuleSelection]) -> Bool? {
        rules.last(where: { $0.field == field }).map { SearchRuleSelection.booleanValue(from: $0.value) }
    }

    private static func intRule(
        for field: SearchRuleField,
        in rules: [SearchRuleSelection]
    ) -> (operator: SearchRuleOperator, value: Int)? {
        guard let rule = rules.last(where: { $0.field == field }),
              let value = Int(rule.value.trimmingCharacters(in: .whitespacesAndNewlines)),
              value >= 0 else {
            return nil
        }
        return (rule.operator, value)
    }
}

struct FileKindResolver: Sendable {
    func kindIDs(
        for path: String,
        isDirectory: Bool,
        attributes: [FileAttributeKey: Any]
    ) -> Set<String> {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let fileManager = FileManager.default
        let resourceValues = try? url.resourceValues(forKeys: [.isPackageKey, .isAliasFileKey, .contentTypeKey])
        let fileType = attributes[.type] as? FileAttributeType
        var ids: Set<String> = []

        if fileType == .typeSymbolicLink {
            ids.formUnion(["kind.symlink", "kind.alias_or_symlink"])
            return ids
        }

        if resourceValues?.isAliasFile == true || ext == "alias" {
            ids.formUnion(["kind.finder_alias", "kind.alias_or_symlink"])
        }

        if isDirectory {
            if ext == "app" {
                ids.insert("kind.application")
                return ids
            }
            if resourceValues?.isPackage == true || Self.packageExtensions.contains(ext) {
                ids.insert("kind.package")
            }
            ids.formUnion(["kind.folder", "kind.directory"])
            return ids
        }

        ids.insert("kind.file")

        if let explicitKind = Self.explicitExtensionKinds[ext] {
            ids.formUnion(explicitKind)
        }

        if fileManager.isExecutableFile(atPath: path) {
            ids.insert("kind.unix_executable")
        }

        if let contentType = resourceValues?.contentType ?? UTType(filenameExtension: ext) {
            if contentType.conforms(to: .audio) {
                ids.insert("kind.audio")
            }
            if contentType.conforms(to: .font) {
                ids.insert("kind.font")
            }
            if contentType.conforms(to: .image) {
                ids.insert("kind.image")
            }
            if contentType.conforms(to: .movie) || contentType.conforms(to: .audiovisualContent) {
                ids.insert("kind.video")
            }
            if contentType.conforms(to: .pdf) {
                ids.insert("kind.pdf")
            }
            if contentType.conforms(to: .plainText) {
                ids.formUnion(["kind.plain_text", "kind.text"])
            } else if contentType.conforms(to: .text) {
                ids.insert("kind.text")
            }
            if contentType.conforms(to: .archive) {
                ids.insert("kind.archive")
            }
        }

        return ids
    }

    func displayTitle(
        for path: String,
        isDirectory: Bool,
        attributes: [FileAttributeKey: Any]
    ) -> String {
        let ids = kindIDs(for: path, isDirectory: isDirectory, attributes: attributes)
        let primaryID = Self.displayPriority.first(where: { ids.contains($0) }) ?? "kind.file"
        return L10n.string(Self.localizedTitleKey(for: primaryID))
    }

    private static func localizedTitleKey(for id: String) -> String {
        switch id {
        case "kind.any":
            return "search_rule.kind.any"
        case "kind.alias_or_symlink":
            return "search_rule.kind.alias_or_symlink"
        case "kind.applescript":
            return "search_rule.kind.applescript"
        case "kind.application":
            return "search_rule.kind.application"
        case "kind.archive":
            return "search_rule.kind.archive"
        case "kind.audio":
            return "search_rule.kind.audio"
        case "kind.directory":
            return "search_rule.kind.directory"
        case "kind.disk_image":
            return "search_rule.kind.disk_image"
        case "kind.ebook":
            return "search_rule.kind.ebook"
        case "kind.finder_alias":
            return "search_rule.kind.finder_alias"
        case "kind.folder":
            return "search_rule.kind.folder"
        case "kind.font":
            return "search_rule.kind.font"
        case "kind.image":
            return "search_rule.kind.image"
        case "kind.package":
            return "search_rule.kind.package"
        case "kind.pdf":
            return "search_rule.kind.pdf"
        case "kind.plain_text":
            return "search_rule.kind.plain_text"
        case "kind.presentation":
            return "search_rule.kind.presentation"
        case "kind.spreadsheet":
            return "search_rule.kind.spreadsheet"
        case "kind.symlink":
            return "search_rule.kind.symlink"
        case "kind.text":
            return "search_rule.kind.text"
        case "kind.unix_executable":
            return "search_rule.kind.unix_executable"
        case "kind.video":
            return "search_rule.kind.video"
        case "kind.word_pages":
            return "search_rule.kind.word_pages"
        default:
            return "search_rule.kind.file"
        }
    }

    private static let packageExtensions: Set<String> = ["bundle", "framework", "plugin", "xcodeproj", "playground"]

    private static let explicitExtensionKinds: [String: Set<String>] = [
        "alias": ["kind.finder_alias", "kind.alias_or_symlink"],
        "scpt": ["kind.applescript"],
        "applescript": ["kind.applescript"],
        "app": ["kind.application"],
        "zip": ["kind.archive"],
        "tar": ["kind.archive"],
        "gz": ["kind.archive"],
        "tgz": ["kind.archive"],
        "bz2": ["kind.archive"],
        "7z": ["kind.archive"],
        "rar": ["kind.archive"],
        "dmg": ["kind.disk_image"],
        "epub": ["kind.ebook"],
        "numbers": ["kind.spreadsheet"],
        "xls": ["kind.spreadsheet"],
        "xlsx": ["kind.spreadsheet"],
        "ppt": ["kind.presentation"],
        "pptx": ["kind.presentation"],
        "key": ["kind.presentation"],
        "doc": ["kind.word_pages"],
        "docx": ["kind.word_pages"],
        "pages": ["kind.word_pages"]
    ]

    private static let displayPriority: [String] = [
        "kind.application",
        "kind.package",
        "kind.finder_alias",
        "kind.symlink",
        "kind.folder",
        "kind.directory",
        "kind.disk_image",
        "kind.ebook",
        "kind.archive",
        "kind.applescript",
        "kind.audio",
        "kind.font",
        "kind.image",
        "kind.pdf",
        "kind.presentation",
        "kind.spreadsheet",
        "kind.word_pages",
        "kind.plain_text",
        "kind.text",
        "kind.unix_executable",
        "kind.video",
        "kind.file"
    ]
}

private extension SearchExecutor {
    static func isInsidePackageContents(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).pathComponents
        guard components.count > 1 else {
            return false
        }

        var currentPath = ""
        for component in components.dropLast() {
            currentPath = (currentPath as NSString).appendingPathComponent(component)
            if isPackagePath(currentPath) {
                return true
            }
        }

        return false
    }

    static func isInsidePackageContents(_ path: String, relativeTo rootPath: String) -> Bool {
        let rootURL = URL(fileURLWithPath: rootPath)
        let pathURL = URL(fileURLWithPath: path)
        let components = pathURL.pathComponents.dropFirst(rootURL.pathComponents.count)
        guard components.isEmpty == false else {
            return false
        }

        var currentPath = rootPath
        for component in components.dropLast() {
            currentPath = (currentPath as NSString).appendingPathComponent(component)
            if isPackagePath(currentPath) {
                return true
            }
        }

        return false
    }
}
