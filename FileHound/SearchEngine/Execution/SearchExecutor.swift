import Darwin
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

/// 执行一次搜索。executeStreaming 会阻塞调用线程直到搜索结束，应在专用线程上调用（见 SearchWorkflowController），
/// 不要放进 Swift 并发的协作线程池：内部的等待会占住线程，多个窗口同时搜索时会饿死线程池
struct SearchExecutor: Sendable {
    fileprivate let walker: DirectoryWalker
    fileprivate let provider: any FilesystemAccessProviding
    fileprivate let spotlightSearchService: SpotlightSearchService
    fileprivate let catalogSearcher: (any VolumeCatalogSearching)?
    private let specialFoldersStore: SpecialFoldersStore
    private let specialFolderPlanner: SpecialFolderPlanner
    private let fileKindResolver: FileKindResolver
    private let nowProvider: @Sendable () -> Date
    private let contentMatcher = ContentMatcher()
    private let scriptSourceReader = ScriptSourceReader()

    init(
        walker: DirectoryWalker = DirectoryWalker(),
        provider: any FilesystemAccessProviding = LocalFilesystemProvider(),
        spotlightSearchService: SpotlightSearchService = SpotlightSearchService(),
        catalogSearcher: (any VolumeCatalogSearching)? = nil,
        specialFoldersStore: SpecialFoldersStore = .shared,
        specialFolderPlanner: SpecialFolderPlanner = SpecialFolderPlanner(),
        fileKindResolver: FileKindResolver = FileKindResolver(),
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.walker = walker
        self.provider = provider
        self.spotlightSearchService = spotlightSearchService
        // 卷目录搜索直接读取真实文件系统，只在使用本地文件访问时默认启用
        self.catalogSearcher = catalogSearcher ?? (provider is LocalFilesystemProvider ? LocalVolumeCatalogSearcher() : nil)
        self.specialFoldersStore = specialFoldersStore
        self.specialFolderPlanner = specialFolderPlanner
        self.fileKindResolver = fileKindResolver
        self.nowProvider = nowProvider
    }

    func execute(
        request: SearchRequest,
        options: SearchExecutionOptions = SearchExecutionOptions(),
        cancellation: SearchCancellationToken = SearchCancellationToken()
    ) -> SearchExecutionResult {
        executeStreaming(request: request, options: options, cancellation: cancellation)
    }

    /// 流程：Spotlight 预取（可选）在后台线程与卷目录搜索 / 遍历并行，结果都汇总到同一个 collector 按路径去重。
    /// cancellation 被取消后尽快返回；达到数量上限时停止所有阶段并返回已找到的结果
    func executeStreaming(
        request: SearchRequest,
        options: SearchExecutionOptions = SearchExecutionOptions(),
        cancellation: SearchCancellationToken = SearchCancellationToken(),
        onProgress: (@Sendable (SearchExecutionProgress) -> Void)? = nil
    ) -> SearchExecutionResult {
        let run = SearchRun(
            executor: self,
            request: request,
            includeSpotlight: options.includeSpotlightResults,
            cancellation: cancellation,
            onProgress: onProgress
        )
        return run.execute()
    }

    // MARK: - 卷目录搜索的名称片段

    /// 从名称类规则中取一段名称必然包含的文字（规则之间是“且”关系，任取一条都成立），取最长的一段以减少候选项。
    /// 规则值需已规范化（去掉首尾空白，扩展名去掉首尾的 “.”）
    static func catalogNameFragment(for rules: [SearchRuleSelection], diacriticsSensitive: Bool) -> String? {
        rules
            .flatMap(requiredNameSubstrings(of:))
            .flatMap { catalogSafeRuns(of: $0, diacriticsSensitive: diacriticsSensitive) }
            .filter { $0.utf8.count >= 2 }
            .max { $0.utf8.count < $1.utf8.count }
    }

    /// 满足规则的名称一定包含的子串
    private static func requiredNameSubstrings(of rule: SearchRuleSelection) -> [String] {
        let value = rule.value
        guard value.isEmpty == false else {
            return []
        }
        let terms = value.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)

        switch (rule.field, rule.operator) {
        case (.name, .contains), (.name, .beginsWith), (.name, .endsWith), (.name, .isExactly),
             (.nameWithoutExtension, .contains), (.nameWithoutExtension, .beginsWith),
             (.nameWithoutExtension, .endsWith), (.nameWithoutExtension, .isExactly):
            return [value]
        case (.name, .containsWords), (.name, .containsPhrase),
             (.nameWithoutExtension, .containsWords), (.nameWithoutExtension, .containsPhrase):
            return terms
        case (.name, .matchesPattern):
            return value.split(whereSeparator: { $0 == "*" || $0 == "?" }).map(String.init)
        case (.extensionName, .isExactly), (.extensionName, .beginsWith):
            return ["." + value]
        case (.extensionName, .endsWith), (.extensionName, .contains):
            return [value]
        default:
            return []
        }
    }

    /// searchfs 把双方分解为 NFD 后折叠大小写再做子串匹配，区分变音符号：组合符号插在基本字母之后，
    /// 名称里任何一个字母带了变音，都会把片段在名称中的连续出现打断（“Resume” 命中不了 “Résumé”）。
    /// 所以忽略变音符号时，可能带变音的字母（各拼音文字的字母）都不能放进片段，只用数字、标点、汉字等组成的片段；
    /// 大小写映射会改变长度的字符（如 ß、İ）在两边的折叠规则不一致，也要切开。
    /// 这意味着默认设置下纯字母的名称搜索不会用 searchfs，改为遍历（约慢 1.5 倍）；区分变音符号时照常使用
    private static func catalogSafeRuns(of value: String, diacriticsSensitive: Bool) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in value {
            let text = String(character)
            let scalarCount = text.unicodeScalars.count
            let keepsLength = text.lowercased().unicodeScalars.count == scalarCount
                && text.uppercased().unicodeScalars.count == scalarCount
            let isSafe: Bool
            if keepsLength == false {
                isSafe = false
            } else if diacriticsSensitive {
                isSafe = true
            } else {
                isSafe = DiacriticFolding.mayCarryDiacritics(character) == false
                    && text.folding(options: .diacriticInsensitive, locale: nil) == text
            }
            if isSafe {
                current.append(character)
            } else if current.isEmpty == false {
                runs.append(current)
                current = ""
            }
        }
        if current.isEmpty == false {
            runs.append(current)
        }
        return runs
    }

    // MARK: - 路径工具

    fileprivate static let dataVolumePath = "/System/Volumes/Data"

    fileprivate static func trimmingTrailingSlash(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    fileprivate static func directoryPrefix(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    fileprivate static func isStrictDescendant(_ path: String, of ancestor: String) -> Bool {
        path != ancestor && path.hasPrefix(directoryPrefix(ancestor))
    }

    /// 去掉重复的根目录（忽略末尾的 “/”），保留首次出现的顺序。嵌套的根目录由遍历器负责不重复进入
    fileprivate static func uniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert(trimmingTrailingSlash($0)).inserted }
    }

    /// 多根搜索时，条目的深度、包内容判断都相对于包含它的最深根目录
    static func rootPath(containing path: String, in rootPaths: [String]) -> String {
        rootPaths
            .filter { isSameOrDescendant(path, of: $0) }
            .max { $0.count < $1.count } ?? rootPaths.first ?? "/"
    }

    /// 排除路径不作用于它所包含的搜索根之内：例如“所有磁盘”既排除 /Volumes，又把各外置卷作为搜索根
    static func isExcluded(_ path: String, by excludedPaths: [String], rootPath: String) -> Bool {
        excludedPaths.contains { isSameOrDescendant(path, of: $0) && isSameOrDescendant(rootPath, of: $0) == false }
    }

    fileprivate static func isSameOrDescendant(_ path: String, of ancestor: String) -> Bool {
        path == ancestor || path.hasPrefix(ancestor.hasSuffix("/") ? ancestor : ancestor + "/")
    }

    // MARK: - 规则判定

    /// 规则之间是“且”关系，先判定只看路径的廉价规则，读属性、读内容的规则放到最后
    fileprivate static func evaluationCost(of field: SearchRuleField) -> Int {
        switch field {
        case .name, .extensionName, .nameWithoutExtension, .path, .folderNames,
             .caseSensitive, .diacriticsSensitive, .invisibleItems, .packageContents,
             .trashedContents, .limitFolderDepth, .limitAmount:
            return 0
        case .lastModifiedDate, .createdDate, .fileSize, .kind:
            return 1
        case .lastOpenedDate, .tag, .comments:
            return 2
        case .script, .textContent:
            return 3
        }
    }

    fileprivate static func orderedByEvaluationCost(_ rules: [PreparedSearchRule]) -> [PreparedSearchRule] {
        rules.enumerated()
            .sorted { (evaluationCost(of: $0.element.field), $0.offset) < (evaluationCost(of: $1.element.field), $1.offset) }
            .map(\.element)
    }

    fileprivate func matches(
        entry: DirectoryEntry,
        attributes: [FileAttributeKey: Any],
        rule: PreparedSearchRule,
        behavior: SearchRuleExecutionBehavior
    ) throws -> Bool {
        // 没填值的规则不参与判定；“今天”“昨天”本来就没有值，不能因此被当成恒成立
        guard rule.value.isEmpty == false
                || SearchRuleExecutionBehavior.globalFields.contains(rule.field)
                || rule.operator == .isToday
                || rule.operator == .isYesterday else {
            return true
        }

        switch rule.field {
        case .name:
            return matchString(entry.lastPathComponent, using: rule, behavior: behavior)
        case .extensionName:
            return matchString((entry.lastPathComponent as NSString).pathExtension, using: rule, behavior: behavior)
        case .nameWithoutExtension:
            let name = (entry.lastPathComponent as NSString).deletingPathExtension
            return matchString(name, using: rule, behavior: behavior)
        case .lastModifiedDate:
            return compareDate(attributes[.modificationDate] as? Date, using: rule)
        case .createdDate:
            return compareDate(attributes[.creationDate] as? Date, using: rule)
        case .lastOpenedDate:
            let resourceValues = try? URL(fileURLWithPath: entry.path, isDirectory: entry.isDirectory).resourceValues(forKeys: [.contentAccessDateKey])
            return compareDate(resourceValues?.contentAccessDate, using: rule)
        case .fileSize:
            let size = (attributes[.size] as? NSNumber)?.int64Value
            return compareNumber(size, using: rule)
        case .kind:
            return compareKind(entry: entry, attributes: attributes, using: rule)
        case .tag:
            let resourceValues = try? URL(fileURLWithPath: entry.path, isDirectory: entry.isDirectory).resourceValues(forKeys: [.tagNamesKey])
            return matchAnyComponent(resourceValues?.tagNames ?? [], using: rule, behavior: behavior)
        case .comments:
            return matchString(FinderCommentReader.comment(atPath: entry.path) ?? "", using: rule, behavior: behavior)
        case .path:
            return matchString(entry.path, using: rule, behavior: behavior)
        case .folderNames:
            let folderNames = ((entry.path as NSString).deletingLastPathComponent as NSString)
                .pathComponents
                .filter { $0 != "/" }
            return matchAnyComponent(folderNames, using: rule, behavior: behavior)
        case .textContent:
            guard entry.isDirectory == false else {
                return false
            }
            // 非“包含”类运算符要整份解码，超大文件直接判为不命中，连读取（映射与预读）也省掉
            if ContentMatcher.isContainsOperator(rule.operator) == false,
               let size = (attributes[.size] as? NSNumber)?.int64Value,
               size > Int64(ContentMatcher.maximumDecodedContentSize) {
                return false
            }

            let data = try provider.contentsOfFile(atPath: entry.path)
            return try contentMatcher.matches(
                data: data,
                rule: rule.selection,
                compareOptions: behavior.stringCompareOptions,
                caseSensitive: behavior.caseSensitive,
                regex: rule.regex
            )
        case .script:
            let source = scriptSourceReader.source(
                atPath: entry.path,
                isDirectory: entry.isDirectory,
                fileSize: (attributes[.size] as? NSNumber)?.int64Value,
                readContents: provider.contentsOfFile(atPath:)
            )
            guard let source else {
                return false
            }
            return matchString(source, using: rule, behavior: behavior)
        case .caseSensitive, .diacriticsSensitive, .invisibleItems, .packageContents, .trashedContents, .limitFolderDepth, .limitAmount:
            return true
        }
    }

    fileprivate func makeResultItem(
        for entry: DirectoryEntry,
        attributes: [FileAttributeKey: Any],
        presentation: ResultPresentation
    ) -> SearchResultItem {
        let url = URL(fileURLWithPath: entry.path, isDirectory: entry.isDirectory)
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
            matchReason: presentation.matchReasons.reason(isDirectory: entry.isDirectory),
            previewSnippet: presentation.preview,
            highlightKind: presentation.highlight?.kind,
            highlightQuery: presentation.highlight?.query,
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

    fileprivate static func highlightMetadata(for rules: [PreparedSearchRule]) -> (kind: SearchResultHighlightKind, query: String)? {
        for rule in rules {
            guard rule.value.isEmpty == false, isPositiveHighlightOperator(rule.operator) else {
                continue
            }

            switch rule.field {
            case .name:
                return (.name, rule.value)
            case .extensionName:
                return (.extensionName, rule.value)
            default:
                continue
            }
        }

        return nil
    }

    /// 结果行的预览文字：取第一条有值的普通条件，按界面上的显示方式转换（类型显示为本地化名称），开关类条件不参与
    fileprivate static func previewText(for rules: [PreparedSearchRule]) -> String {
        guard let rule = rules.first(where: {
            SearchRuleExecutionBehavior.globalFields.contains($0.field) == false && $0.value.isEmpty == false
        }) else {
            return ""
        }
        return rule.field.definition.displayValue(for: rule.value, operator: rule.operator)
    }

    /// 字符串匹配。op 用于多值字段把否定运算符换成对应的肯定运算符，默认使用规则自身的运算符
    private func matchString(
        _ candidate: String,
        using rule: PreparedSearchRule,
        behavior: SearchRuleExecutionBehavior,
        operator op: SearchRuleOperator? = nil
    ) -> Bool {
        let value = rule.value
        let options = behavior.stringCompareOptions

        switch op ?? rule.operator {
        case .contains:
            return candidate.range(of: value, options: options) != nil
        case .containsPhrase, .containsWords:
            return matchWholeWords(candidate, regexes: rule.wordRegexes, behavior: behavior)
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
        case .containsAnyOf:
            return rule.terms.contains { candidate.range(of: $0, options: options) != nil }
        case .beginsWithAnyOf:
            return rule.terms.contains { candidate.range(of: $0, options: options.union(.anchored)) != nil }
        case .endsWithAnyOf:
            return rule.terms.contains {
                candidate.range(of: $0, options: options.union(.backwards))?.upperBound == candidate.endIndex
            }
        case .isAnyOf:
            return rule.terms.contains { candidate.compare($0, options: options) == .orderedSame }
        case .matchesPattern, .matchesRegex:
            return rule.regex.map { Self.firstMatch($0, in: candidate) } ?? false
        case .doesNotMatchRegex:
            // 非法正则无法判定，按不命中处理，而不是让“不匹配”命中所有条目
            return rule.regex.map { Self.firstMatch($0, in: candidate) == false } ?? false
        case .isGreaterThan, .isLessThan, .isBefore, .isAfter, .isOnOrBefore, .isOnOrAfter, .isWithinTheLast, .isToday, .isYesterday:
            return false
        }
    }

    /// 多值字段（标签、各级文件夹名）：肯定类运算符任一值命中即可，否定类运算符要求所有值都不命中
    private func matchAnyComponent(
        _ components: [String],
        using rule: PreparedSearchRule,
        behavior: SearchRuleExecutionBehavior
    ) -> Bool {
        let positiveOperator: SearchRuleOperator?
        switch rule.operator {
        case .isNot:
            positiveOperator = .isExactly
        case .doesNotContain:
            positiveOperator = .contains
        case .doesNotMatchRegex:
            // 非法正则无法判定，不命中
            guard rule.regex != nil else {
                return false
            }
            positiveOperator = .matchesRegex
        default:
            positiveOperator = nil
        }

        guard let positiveOperator else {
            return components.contains { matchString($0, using: rule, behavior: behavior) }
        }
        return components.contains { matchString($0, using: rule, behavior: behavior, operator: positiveOperator) } == false
    }

    /// 以单词边界匹配短语（正则在规则准备阶段编译）；“包含单词”要求每个词都出现
    private func matchWholeWords(
        _ candidate: String,
        regexes: [NSRegularExpression],
        behavior: SearchRuleExecutionBehavior
    ) -> Bool {
        guard regexes.isEmpty == false else {
            return false
        }
        let foldedCandidate = behavior.diacriticsSensitive
            ? candidate
            : candidate.folding(options: .diacriticInsensitive, locale: nil)
        return regexes.allSatisfy { Self.firstMatch($0, in: foldedCandidate) }
    }

    private static func firstMatch(_ regex: NSRegularExpression, in candidate: String) -> Bool {
        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        return regex.firstMatch(in: candidate, options: [], range: range) != nil
    }

    private func compareKind(
        entry: DirectoryEntry,
        attributes: [FileAttributeKey: Any],
        using rule: PreparedSearchRule
    ) -> Bool {
        let kindIDs = fileKindResolver.kindIDs(for: entry.path, isDirectory: entry.isDirectory, attributes: attributes)
        let value = rule.value

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

    private func compareNumber(_ candidate: Int64?, using rule: PreparedSearchRule) -> Bool {
        guard let candidate, let target = rule.byteCount else {
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

    /// 日期界限在规则准备阶段已换算成区间，这里只做比较
    private func compareDate(_ candidate: Date?, using rule: PreparedSearchRule) -> Bool {
        guard let candidate, let range = rule.dateRange else {
            return false
        }
        return range.contains(candidate)
    }

    private static func displayDate(_ date: Date?) -> String {
        guard let date else {
            return ""
        }

        return displayDateFormatter.string(from: date)
    }

    // 格式化器创建开销大，结果项数量多时复用；两者的 string(from:) 均可跨线程调用
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let displaySizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()

    private static func displaySize(byteCount: Int64?) -> String {
        guard let byteCount else {
            return ""
        }

        return displaySizeFormatter.string(fromByteCount: byteCount)
    }

    private static let packagePathExtensions: Set<String> = ["app", "bundle", "framework", "plugin", "xcodeproj", "playground"]

    private static func isPackagePath(_ path: String) -> Bool {
        packagePathExtensions.contains((path as NSString).pathExtension.lowercased())
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

/// 结果行里与具体条目无关、每次搜索只算一次的展示信息
private struct ResultPresentation: Sendable {
    let preview: String
    let highlight: (kind: SearchResultHighlightKind, query: String)?
    let matchReasons: MatchReasons
}

/// 每次搜索只查一次本地化文案：L10n 每次调用都会重新加载语言包，不适合在遍历中逐项调用
private struct MatchReasons: Sendable {
    private let highlighted: String?
    private let folder: String
    private let name: String

    init(highlight: (kind: SearchResultHighlightKind, query: String)?) {
        switch highlight?.kind {
        case .name:
            highlighted = L10n.string("search_result.match_reason.name")
        case .extensionName:
            highlighted = L10n.string("search_result.match_reason.extension")
        case nil:
            highlighted = nil
        }
        folder = L10n.string("search_result.match_reason.folder")
        name = L10n.string("search_result.match_reason.name")
    }

    func reason(isDirectory: Bool) -> String {
        highlighted ?? (isDirectory ? folder : name)
    }
}

// MARK: - 一次搜索的执行过程

/// 一次搜索用到的全部状态。遍历线程、卷目录搜索线程与 Spotlight 线程并发调用其中的判定方法
private final class SearchRun: @unchecked Sendable {
    private let executor: SearchExecutor
    private let request: SearchRequest
    private let includeSpotlight: Bool
    private let behavior: SearchRuleExecutionBehavior
    /// 规范化、预解析后的规则，按判定成本排序
    private let matchingRules: [PreparedSearchRule]
    private let hasTextContentRule: Bool
    /// 去重后的搜索根
    private let rootPaths: [String]
    /// 每个搜索根各自的特殊文件夹规划
    private let planningByRoot: [String: SpecialFolderPlanningResult]
    private let presentation: ResultPresentation
    private let collector: SearchResultCollector
    /// 用户取消或达到数量上限时置位，遍历、卷目录搜索与 Spotlight 都据此停止
    private let stopToken: SearchCancellationToken
    private let hiddenPaths = HiddenPathChecker()
    /// 是否在判定前先查已收集的路径：多个阶段可能送来同一条目，规则需要读属性或内容时跳过重复判定更省事
    private var checksDuplicates = false

    init(
        executor: SearchExecutor,
        request: SearchRequest,
        includeSpotlight: Bool,
        cancellation: SearchCancellationToken,
        onProgress: (@Sendable (SearchExecutionProgress) -> Void)?
    ) {
        self.executor = executor
        self.request = request
        self.includeSpotlight = includeSpotlight
        let behavior = SearchRuleExecutionBehavior(rules: request.rules)
        self.behavior = behavior
        let now = executor.currentDate()
        let preparedRules = request.rules.map {
            PreparedSearchRule(
                $0,
                caseSensitive: behavior.caseSensitive,
                diacriticsSensitive: behavior.diacriticsSensitive,
                now: now
            )
        }
        matchingRules = SearchExecutor.orderedByEvaluationCost(preparedRules)
        hasTextContentRule = preparedRules.contains { $0.field == .textContent && $0.value.isEmpty == false }
        rootPaths = SearchExecutor.uniquePaths(request.rootPaths)
        planningByRoot = executor.specialFolderPlanning(for: rootPaths)
        let highlight = SearchExecutor.highlightMetadata(for: preparedRules)
        presentation = ResultPresentation(
            preview: SearchExecutor.previewText(for: preparedRules),
            highlight: highlight,
            matchReasons: MatchReasons(highlight: highlight)
        )
        collector = SearchResultCollector(title: request.queryTitle, limit: behavior.limitAmount, onProgress: onProgress)
        stopToken = SearchCancellationToken(parent: cancellation)
    }

    private var isStopped: Bool {
        stopToken.isCancelled
    }

    func execute() -> SearchExecutionResult {
        // “数量少于 1” 等同于不要结果
        guard behavior.limitAmount != 0, isStopped == false else {
            return collector.result()
        }

        let catalogPlan = catalogSearchPlan()
        let runsSpotlight = includeSpotlight && executor.spotlightSearchService.buildQuery(from: request.rules) != nil
        checksDuplicates = (runsSpotlight || catalogPlan != nil)
            && matchingRules.contains { SearchExecutor.evaluationCost(of: $0.field) >= 2 }

        // Spotlight 预取在后台与卷目录搜索 / 遍历并行，先给出第一屏结果，不拖慢后面的完整搜索
        let spotlightToken = SearchCancellationToken(parent: stopToken)
        let spotlightGroup = DispatchGroup()
        if runsSpotlight {
            spotlightGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { spotlightGroup.leave() }
                runSpotlightPrefetch(stopToken: spotlightToken)
            }
        }

        var walkRoots = rootPaths
        if let catalogPlan {
            if let fallbackRoots = runCatalogSearch(catalogPlan) {
                walkRoots = SearchExecutor.uniquePaths(catalogPlan.walkRoots + fallbackRoots)
            } else {
                walkRoots = []
            }
        }

        if walkRoots.isEmpty == false, isStopped == false {
            let plan = SearchPlan(
                rootPaths: walkRoots,
                specialFolderPlanning: walkRoots.map { planning(for: $0) }
            )
            executor.walker.walk(
                plan: plan,
                includeHiddenFiles: behavior.includeInvisibleItems,
                cancellation: stopToken
            ) { [self] entry in
                evaluate(entry)
            }
        }

        // 等 Spotlight 预取结束再返回：它能补充遍历进不去的目录中的条目，以及 PDF、Office 等读取原始字节无法判定的内容命中。
        // 它与遍历并行，通常早已结束；取消或达到数量上限时 spotlightToken 随 stopToken 一起失效，mdfind 会被立即结束
        spotlightGroup.wait()

        return collector.result()
    }

    // MARK: 逐项判定

    /// 遍历与卷目录搜索共用的逐项判定，可在多个线程上并发调用
    private func evaluate(_ entry: DirectoryEntry) -> DirectoryWalkControl {
        let rootPath = SearchExecutor.rootPath(containing: entry.path, in: rootPaths)
        guard SearchExecutor.isExcluded(entry.path, by: request.excludedPaths, rootPath: rootPath) == false else {
            return .skipDescendants
        }

        // 先算是否进入子目录，已收集过的条目也要遵守深度、包内容等剪枝
        let descendControl: DirectoryWalkControl =
            behavior.shouldDescend(into: entry, rootPath: rootPath) ? .continue : .skipDescendants

        if checksDuplicates, collector.contains(entry.path) {
            return collector.hasReachedLimit ? .stop : descendControl
        }

        guard behavior.allows(entry: entry, rootPath: rootPath),
              let item = matchedItem(for: entry, rootPath: rootPath, trustsTextContent: false, attributes: nil) else {
            return descendControl
        }
        return append(item) ? descendControl : .stop
    }

    /// 按全部规则判定条目，命中时生成结果行。trustsTextContent 为 true 时跳过文本内容规则（已由 Spotlight 判定）
    private func matchedItem(
        for entry: DirectoryEntry,
        rootPath: String,
        trustsTextContent: Bool,
        attributes preloaded: [FileAttributeKey: Any]?
    ) -> SearchResultItem? {
        do {
            // 属性只在规则需要或条目命中后才读取，绝大多数不命中的条目不再多一次 stat
            var cachedAttributes = preloaded
            func attributes() throws -> [FileAttributeKey: Any] {
                if let cachedAttributes {
                    return cachedAttributes
                }
                let loaded = try executor.provider.attributesOfItem(atPath: entry.path)
                cachedAttributes = loaded
                return loaded
            }

            for rule in matchingRules {
                if trustsTextContent, rule.field == .textContent {
                    continue
                }
                let ruleAttributes = rule.needsAttributes ? try attributes() : [:]
                guard try executor.matches(entry: entry, attributes: ruleAttributes, rule: rule, behavior: behavior) else {
                    return nil
                }
            }

            let item = executor.makeResultItem(for: entry, attributes: try attributes(), presentation: presentation)
            guard behavior.allows(item: item, rootPath: rootPath) else {
                return nil
            }
            return item
        } catch {
            return nil
        }
    }

    /// 返回 false 表示已达到数量上限，各阶段都应停止
    private func append(_ item: SearchResultItem) -> Bool {
        guard collector.append(item) == .reachedLimit else {
            return true
        }
        stopToken.cancel()
        return false
    }

    private func planning(for path: String) -> SpecialFolderPlanningResult {
        planningByRoot[SearchExecutor.rootPath(containing: path, in: rootPaths)] ?? SpecialFolderPlanningResult()
    }

    // MARK: Spotlight 预取

    private func runSpotlightPrefetch(stopToken spotlightToken: SearchCancellationToken) {
        let shouldStop: @Sendable () -> Bool = { spotlightToken.isCancelled }
        let trustsTextContent = SpotlightSearchService.trustsTextContentHits(
            caseSensitive: behavior.caseSensitive,
            diacriticsSensitive: behavior.diacriticsSensitive
        )
        let service = executor.spotlightSearchService
        for rootPath in rootPaths {
            guard shouldStop() == false else {
                return
            }
            // 查询失败（如 mdfind 超时）时已回调的结果保留，其余由遍历补全
            _ = try? service.search(rootPath: rootPath, rules: request.rules, shouldStop: shouldStop) { [self] path in
                handleSpotlightPath(path, trustsTextContent: trustsTextContent, stopToken: spotlightToken)
            }
            _ = try? service.searchTextContentCandidates(rootPath: rootPath, rules: request.rules, shouldStop: shouldStop) { [self] path in
                handleSpotlightPath(path, trustsTextContent: false, stopToken: spotlightToken)
            }
        }
    }

    /// Spotlight 结果是近似的候选（不区分大小写、不收录系统目录等），按与遍历相同的条件过滤并复核每条规则
    private func handleSpotlightPath(_ path: String, trustsTextContent: Bool, stopToken spotlightToken: SearchCancellationToken) {
        guard spotlightToken.isCancelled == false, collector.contains(path) == false else {
            return
        }

        let rootPath = SearchExecutor.rootPath(containing: path, in: rootPaths)
        guard SearchExecutor.isStrictDescendant(path, of: SearchExecutor.trimmingTrailingSlash(rootPath)),
              SearchExecutor.isExcluded(path, by: request.excludedPaths, rootPath: rootPath) == false,
              planning(for: path).allows(path: path) else {
            return
        }
        // 遍历不会进入不可见目录，这里补查搜索根以下的每一级
        if behavior.includeInvisibleItems == false, hiddenPaths.hasHiddenComponent(path, below: rootPath) {
            return
        }

        guard let attributes = try? executor.provider.attributesOfItem(atPath: path) else {
            return
        }
        let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
        // 文件夹没有文本内容：Spotlight 的内容查询偶尔也会返回文件夹（如带文本属性的包），一律排除
        if hasTextContentRule, isDirectory {
            return
        }

        let entry = DirectoryEntry(
            path: path,
            isDirectory: isDirectory,
            isHidden: (path as NSString).lastPathComponent.hasPrefix(".")
        )
        guard behavior.allows(entry: entry, rootPath: rootPath),
              let item = matchedItem(for: entry, rootPath: rootPath, trustsTextContent: trustsTextContent, attributes: attributes) else {
            return
        }
        _ = append(item)
    }

    // MARK: 卷目录搜索

    /// 以整个卷为搜索根、且至少有一条规则要求名称包含某段文字时，用 searchfs 在卷目录中按名称预筛选，
    /// 代替逐个目录遍历；候选项仍按完整规则复核。不满足条件的根目录照常遍历
    private func catalogSearchPlan() -> CatalogSearchPlan? {
        // 深度限制依赖遍历时逐层剪枝，卷目录搜索无法提前排除深层目录
        guard let catalogSearcher = executor.catalogSearcher,
              behavior.maximumFolderDepth == nil,
              let nameFragment = SearchExecutor.catalogNameFragment(
                for: matchingRules.map(\.selection),
                diacriticsSensitive: behavior.diacriticsSensitive
              ) else {
            return nil
        }

        let mountPoints = Set(catalogSearcher.mountPoints().map(SearchExecutor.trimmingTrailingSlash))
        let dataVolumePath = SearchExecutor.dataVolumePath
        var targets: [CatalogSearchTarget] = []
        var walkRoots: [String] = []

        for rootPath in rootPaths {
            let volumePath = SearchExecutor.trimmingTrailingSlash(rootPath)
            // Data 卷上的条目经固件链接映射到 /Users 等位置，fsgetpath 返回的是映射后的路径，不在 Data 卷挂载点之下
            guard mountPoints.contains(volumePath), volumePath != dataVolumePath else {
                walkRoots.append(rootPath)
                continue
            }

            var rootTargets = [CatalogSearchTarget(volumePath: volumePath, scopeRoot: rootPath, fallbackRoot: rootPath)]
            if volumePath == "/", mountPoints.contains(dataVolumePath) {
                // 启动卷的用户数据在 Data 卷上。只有遍历时也跳过 /System/Volumes/Data（同一文件不会再以该前缀出现），
                // 按固件链接路径返回的 Data 卷结果才与遍历等价
                guard SearchExecutor.isExcluded(dataVolumePath, by: request.excludedPaths, rootPath: rootPath) else {
                    walkRoots.append(rootPath)
                    continue
                }
                rootTargets.append(CatalogSearchTarget(volumePath: dataVolumePath, scopeRoot: rootPath, fallbackRoot: rootPath))
            }

            // searchfs 不跨越挂载点，遍历会进入的嵌套卷需要单独搜索
            let rootPlanning = planning(for: rootPath)
            for mountPoint in mountPoints.sorted()
            where mountPoint != dataVolumePath && SearchExecutor.isStrictDescendant(mountPoint, of: volumePath) {
                guard SearchExecutor.isExcluded(mountPoint, by: request.excludedPaths, rootPath: rootPath) == false,
                      rootPlanning.allows(path: mountPoint),
                      behavior.includeInvisibleItems || hiddenPaths.hasHiddenComponent(mountPoint, below: rootPath) == false else {
                    continue
                }
                rootTargets.append(CatalogSearchTarget(volumePath: mountPoint, scopeRoot: rootPath, fallbackRoot: mountPoint))
            }
            targets += rootTargets
        }

        guard targets.isEmpty == false else {
            return nil
        }
        return CatalogSearchPlan(nameFragment: nameFragment, targets: targets, walkRoots: walkRoots)
    }

    /// 并发搜索各个卷，返回需要改为遍历的根目录（搜索失败的卷）；被取消或达到数量上限时返回 nil
    private func runCatalogSearch(_ plan: CatalogSearchPlan) -> [String]? {
        guard let catalogSearcher = executor.catalogSearcher, isStopped == false else {
            return nil
        }

        let failures = CatalogFailureRecorder()
        let group = DispatchGroup()
        for target in plan.targets {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { group.leave() }
                let scopePrefix = SearchExecutor.directoryPrefix(target.scopeRoot)
                do {
                    try catalogSearcher.search(
                        volumePath: target.volumePath,
                        nameFragment: plan.nameFragment,
                        shouldStop: { self.isStopped }
                    ) { matches in
                        for match in matches {
                            guard isStopped == false else {
                                return
                            }
                            // 与遍历保持一致：只要搜索根之下的条目，跳过特殊文件夹与不可见目录中的内容
                            guard match.path.utf8.count > scopePrefix.utf8.count, match.path.hasPrefix(scopePrefix) else {
                                continue
                            }
                            let rootPath = SearchExecutor.rootPath(containing: match.path, in: rootPaths)
                            guard planning(for: match.path).allows(path: match.path),
                                  behavior.includeInvisibleItems
                                    || hiddenPaths.hasHiddenComponent(match.path, below: rootPath) == false else {
                                continue
                            }
                            let entry = DirectoryEntry(
                                path: match.path,
                                isDirectory: match.isDirectory,
                                isHidden: (match.path as NSString).lastPathComponent.hasPrefix(".")
                            )
                            _ = evaluate(entry)
                        }
                    }
                } catch {
                    // 已回调的结果保留，整个卷改为遍历，重复项由结果汇总去重
                    failures.record(fallbackRoot: target.fallbackRoot)
                }
            }
        }

        // 各卷的 searchfs 每次最多在内核停留 200ms，之间通过 shouldStop 检查取消与数量上限
        group.wait()

        guard isStopped == false else {
            return nil
        }
        return failures.fallbackRoots
    }
}

private extension SearchExecutor {
    func currentDate() -> Date {
        nowProvider()
    }

    /// 每个搜索根各自规划特殊文件夹，排除规则只作用于与它相关的根
    func specialFolderPlanning(for rootPaths: [String]) -> [String: SpecialFolderPlanningResult] {
        let configuration = specialFoldersStore.load()
        var result: [String: SpecialFolderPlanningResult] = [:]
        for rootPath in rootPaths {
            result[rootPath] = specialFolderPlanner.plan(rootPath: rootPath, configuration: configuration)
        }
        return result
    }
}

private struct CatalogSearchTarget: Sendable {
    /// 传给 searchfs 的卷挂载点
    let volumePath: String
    /// 结果所属的搜索根，结果必须位于其下
    let scopeRoot: String
    /// 搜索失败时改为遍历的目录
    let fallbackRoot: String
}

private struct CatalogSearchPlan: Sendable {
    let nameFragment: String
    let targets: [CatalogSearchTarget]
    /// 不适用卷目录搜索、需要遍历的根目录
    let walkRoots: [String]
}

/// 多个卷并发搜索时记录失败、需要改为遍历的卷
private final class CatalogFailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var failedRoots: [String] = []

    var fallbackRoots: [String] {
        lock.lock()
        defer { lock.unlock() }
        return failedRoots
    }

    func record(fallbackRoot: String) {
        lock.lock()
        failedRoots.append(fallbackRoot)
        lock.unlock()
    }
}

/// 判断路径在搜索根以下是否经过不可见的一级（名称以 “.” 开头或带 UF_HIDDEN 标志，如 ~/Library）。
/// 卷目录搜索与 Spotlight 直接给出深层路径，需要补做遍历时逐层跳过不可见目录的判断；目录的结果会缓存
final class HiddenPathChecker: @unchecked Sendable {
    private let lock = NSLock()
    private var directoryCache: [String: Bool] = [:]

    init() {}

    /// 检查 rootPath 以下直到 path 本身的每一级
    func hasHiddenComponent(_ path: String, below rootPath: String) -> Bool {
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else {
            return false
        }
        let components = path.dropFirst(prefix.count).split(separator: "/")
        var current = String(prefix.dropLast())
        for (index, component) in components.enumerated() {
            if component.hasPrefix(".") {
                return true
            }
            current += "/" + component
            let isLast = index == components.count - 1
            if isLast ? Self.hasHiddenFlag(atPath: current) : cachedHiddenFlag(atPath: current) {
                return true
            }
        }
        return false
    }

    private func cachedHiddenFlag(atPath path: String) -> Bool {
        lock.lock()
        let cached = directoryCache[path]
        lock.unlock()
        if let cached {
            return cached
        }
        let hidden = Self.hasHiddenFlag(atPath: path)
        lock.lock()
        directoryCache[path] = hidden
        lock.unlock()
        return hidden
    }

    static func hasHiddenFlag(atPath path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            return false
        }
        return info.st_flags & UInt32(UF_HIDDEN) != 0
    }
}

private struct SearchRuleExecutionBehavior: Sendable {
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
    /// 结果数量上限，nil 表示不限，0 表示不要任何结果
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
            // “少于 1 个” 得到 0，即不要任何结果
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

        guard maximumFolderDepth != nil || minimumFolderDepth != nil else {
            return true
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

    /// 结果行复核：包内容按相对搜索根判断，搜索根本身位于包内（如 /Applications/Xcode.app）时其中的结果不受影响
    func allows(item: SearchResultItem, rootPath: String) -> Bool {
        if includeInvisibleItems == false, item.isInvisible {
            return false
        }
        if includePackageContents == false, SearchExecutor.isInsidePackageContents(item.path, relativeTo: rootPath) {
            return false
        }
        if includeTrashedContents == false, item.isTrashed {
            return false
        }
        return true
    }

    private func relativeDepth(of path: String, rootPath: String) -> Int {
        let pathComponents = (path as NSString).pathComponents
        let rootComponents = (rootPath as NSString).pathComponents
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

/// 并发遍历中汇总结果：按路径去重、执行数量上限，并把进度回调节流到约 100ms 一次
private final class SearchResultCollector: @unchecked Sendable {
    enum AppendOutcome {
        case appended
        case duplicate
        case reachedLimit
    }

    private static let progressInterval: TimeInterval = 0.1

    private let lock = NSLock()
    private let title: String
    /// nil 表示不限；0 表示不接收任何结果
    private let limit: Int?
    private let onProgress: (@Sendable (SearchExecutionProgress) -> Void)?
    private var items: [SearchResultItem] = []
    private var seenPaths = Set<String>()
    private var lastProgressTime: TimeInterval?
    private var hasPendingProgress = false
    private var isTrailingFlushScheduled = false

    init(title: String, limit: Int?, onProgress: (@Sendable (SearchExecutionProgress) -> Void)?) {
        self.title = title
        self.limit = limit
        self.onProgress = onProgress
    }

    var hasReachedLimit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reachedLimitLocked
    }

    func contains(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return seenPaths.contains(path)
    }

    func append(_ item: SearchResultItem) -> AppendOutcome {
        lock.lock()
        defer { lock.unlock() }
        // 已达上限后其他线程仍可能送来结果，丢弃以保证不超过上限
        guard reachedLimitLocked == false else {
            return .reachedLimit
        }
        guard seenPaths.insert(item.path).inserted else {
            return .duplicate
        }
        items.append(item)

        // 在锁内回调以保证进度按结果数递增的顺序送达；达到上限时立即送出最后一批
        let now = ProcessInfo.processInfo.systemUptime
        if onProgress != nil {
            if reachedLimitLocked || lastProgressTime.map({ now - $0 >= Self.progressInterval }) ?? true {
                emitProgressLocked(now: now)
            } else {
                // 被节流的结果在间隔结束后补发，避免之后长时间没有新命中时界面停留在旧的结果上
                hasPendingProgress = true
                scheduleTrailingFlushLocked()
            }
        }
        return reachedLimitLocked ? .reachedLimit : .appended
    }

    private func emitProgressLocked(now: TimeInterval) {
        lastProgressTime = now
        hasPendingProgress = false
        onProgress?(.init(title: title, items: items, matchedCount: items.count))
    }

    private func scheduleTrailingFlushLocked() {
        guard isTrailingFlushScheduled == false else {
            return
        }
        isTrailingFlushScheduled = true
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.progressInterval) { [self] in
            lock.lock()
            defer { lock.unlock() }
            isTrailingFlushScheduled = false
            if hasPendingProgress {
                emitProgressLocked(now: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    func result() -> SearchExecutionResult {
        lock.lock()
        defer { lock.unlock() }
        return SearchExecutionResult(title: title, items: items)
    }

    private var reachedLimitLocked: Bool {
        guard let limit else {
            return false
        }
        return items.count >= limit
    }
}

struct FileKindResolver: Sendable {
    func kindIDs(
        for path: String,
        isDirectory: Bool,
        attributes: [FileAttributeKey: Any]
    ) -> Set<String> {
        let url = URL(fileURLWithPath: path, isDirectory: isDirectory)
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
            // 音频同样遵从 .audiovisualContent，只有 .movie 才是视频
            if contentType.conforms(to: .movie) {
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

extension SearchExecutor {
    /// 判断是否位于某个包内：除最后一级外，任一级目录名带包扩展名即可
    static func isInsidePackageContents(_ path: String) -> Bool {
        (path as NSString).pathComponents.dropLast().contains(where: isPackagePath)
    }
}

private extension SearchExecutor {
    /// 只看搜索根以下的各级目录：搜索根本身在包内时，不因此排除其中的条目
    static func isInsidePackageContents(_ path: String, relativeTo rootPath: String) -> Bool {
        let rootComponentCount = (rootPath as NSString).pathComponents.count
        return (path as NSString).pathComponents
            .dropFirst(rootComponentCount)
            .dropLast()
            .contains(where: isPackagePath)
    }
}
