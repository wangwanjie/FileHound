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
        let specialFolderPlanning = specialFolderPlanner.plan(
            rootPath: request.rootPath,
            configuration: specialFoldersStore.load()
        )
        let behavior = SearchRuleExecutionBehavior(rules: request.rules)
        let highlight = highlightMetadata(for: request.rules)
        let plan = SearchPlan(
            rootPaths: [request.rootPath],
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

                guard behavior.allows(entry: entry, rootPath: request.rootPath) else {
                    return .continue
                }

                do {
                    let attributes = try provider.attributesOfItem(atPath: entry.path)
                    guard try request.rules.allSatisfy({
                        try matches(entry: entry, attributes: attributes, rule: $0, behavior: behavior)
                    }) else {
                        return .continue
                    }

                    let item = try makeResultItem(
                        for: entry,
                        attributes: attributes,
                        preview: request.rules.first?.value ?? "",
                        highlight: highlight
                    )
                    guard behavior.allows(item: item) else {
                        return .continue
                    }
                    _ = appendResult(item)
                    return behavior.hasReachedLimit(items.count) ? .stop : .continue
                } catch {
                    return .continue
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
        highlight: (kind: SearchResultHighlightKind, query: String)?
    ) -> [SearchResultItem]? {
        guard let paths = try? spotlightSearchService.search(rootPath: request.rootPath, rules: request.rules) else {
            return nil
        }

        let uniquePaths = Array(Set(paths)).sorted()
        let preview = request.rules.first?.value ?? ""

        return uniquePaths.compactMap { path in
            guard specialFolderPlanning.allows(path: path) else {
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

            do {
                let attributes = try provider.attributesOfItem(atPath: path)
                return try makeResultItem(for: entry, attributes: attributes, preview: preview, highlight: highlight)
            } catch {
                return nil
            }
        }
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
            return matchString((resourceValues?.tagNames ?? []).joined(separator: ", "), using: rule, behavior: behavior)
        case .comments:
            return false
        case .path:
            return matchString(entry.path, using: rule, behavior: behavior)
        case .folderNames:
            return matchString((entry.path as NSString).deletingLastPathComponent, using: rule, behavior: behavior)
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
            matchReason: highlight.map(matchReason(for:)) ?? (entry.isDirectory ? "文件夹命中" : "名称命中"),
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
            return "名称命中"
        case .extensionName:
            return "扩展名命中"
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
        case .contains, .containsPhrase:
            return candidate.range(of: value, options: options) != nil
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
            return splitTerms(from: value).allSatisfy { candidate.range(of: $0, options: options) != nil }
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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false else {
            return nil
        }

        let numberPart = trimmed.prefix { $0.isNumber || $0 == "." }
        guard let numericValue = Double(numberPart) else {
            return nil
        }

        let unitPart = trimmed.dropFirst(numberPart.count)
        let multiplier: Double
        switch unitPart {
        case "kb":
            multiplier = 1_024
        case "mb":
            multiplier = 1_048_576
        case "gb":
            multiplier = 1_073_741_824
        case "":
            multiplier = 1
        default:
            return nil
        }

        return Int64(numericValue * multiplier)
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
    let limitFolderDepth: Int?
    let limitAmount: Int?

    init(rules: [SearchRuleSelection]) {
        caseSensitive = Self.booleanValue(for: .caseSensitive, in: rules) ?? false
        diacriticsSensitive = Self.booleanValue(for: .diacriticsSensitive, in: rules) ?? false
        includeInvisibleItems = Self.booleanValue(for: .invisibleItems, in: rules) ?? true
        includePackageContents = Self.booleanValue(for: .packageContents, in: rules) ?? true
        includeTrashedContents = Self.booleanValue(for: .trashedContents, in: rules) ?? true
        limitFolderDepth = Self.intValue(for: .limitFolderDepth, in: rules)
        limitAmount = Self.intValue(for: .limitAmount, in: rules)
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

        if let limitFolderDepth, limitFolderDepth >= 0, relativeDepth(of: entry.path, rootPath: rootPath) > limitFolderDepth {
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

    private static func intValue(for field: SearchRuleField, in rules: [SearchRuleSelection]) -> Int? {
        rules.last(where: { $0.field == field }).flatMap {
            Int($0.value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
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
