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
    private let catalogSearcher: (any VolumeCatalogSearching)?
    private let specialFoldersStore: SpecialFoldersStore
    private let specialFolderPlanner: SpecialFolderPlanner
    private let fileKindResolver: FileKindResolver
    private let nowProvider: @Sendable () -> Date
    private let metadataEvaluator = MetadataEvaluator()
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
        let rules = Self.preparedRules(request.rules)
        let specialFolderPlanning = mergedSpecialFolderPlanning(for: request.rootPaths)
        let behavior = SearchRuleExecutionBehavior(rules: rules)
        let highlight = highlightMetadata(for: request.rules)
        let matchReasons = MatchReasons(highlight: highlight)
        let preview = request.rules.first?.value ?? ""
        let collector = SearchResultCollector(
            title: title,
            limit: behavior.limitAmount,
            onProgress: onProgress
        )
        let prefersSpotlightTextResults = options.includeSpotlightResults && spotlightSearchService.canSatisfyTextContentSearch(
            rules: request.rules,
            caseSensitive: behavior.caseSensitive,
            diacriticsSensitive: behavior.diacriticsSensitive
        )

        if options.includeSpotlightResults,
           let spotlightItems = executeSpotlightSearchIfPossible(
                request: request,
                rules: rules,
                specialFolderPlanning: specialFolderPlanning,
                behavior: behavior,
                highlight: highlight,
                matchReasons: matchReasons
           ) {
            for item in spotlightItems where behavior.allows(item: item) {
                if collector.append(item) == .reachedLimit {
                    return collector.result()
                }
            }

            if prefersSpotlightTextResults, collector.isEmpty == false {
                return collector.result()
            }
        }

        // 规则之间是“且”关系，先判定只看路径的廉价规则，读属性、读内容的规则放到最后
        let matchingRules = Self.orderedByEvaluationCost(rules)
        let catalogPlan = catalogSearchPlan(
            request: request,
            rules: rules,
            behavior: behavior,
            specialFolderPlanning: specialFolderPlanning
        )
        let checksDuplicates = collector.isEmpty == false || catalogPlan != nil

        // 遍历与卷目录搜索共用的逐项判定，可在多个线程上并发调用
        let evaluate: @Sendable (DirectoryEntry) -> DirectoryWalkControl = { entry in
            if checksDuplicates, collector.contains(entry.path) {
                return collector.hasReachedLimit ? .stop : .continue
            }

            let rootPath = Self.rootPath(containing: entry.path, in: request.rootPaths)
            guard Self.isExcluded(entry.path, by: request.excludedPaths, rootPath: rootPath) == false else {
                return .skipDescendants
            }

            let descendControl: DirectoryWalkControl =
                behavior.shouldDescend(into: entry, rootPath: rootPath) ? .continue : .skipDescendants

            guard behavior.allows(entry: entry, rootPath: rootPath) else {
                return descendControl
            }

            do {
                // 属性只在规则需要或条目命中后才读取，绝大多数不命中的条目不再多一次 stat
                var cachedAttributes: [FileAttributeKey: Any]?
                func attributes() throws -> [FileAttributeKey: Any] {
                    if let cachedAttributes {
                        return cachedAttributes
                    }
                    let loaded = try provider.attributesOfItem(atPath: entry.path)
                    cachedAttributes = loaded
                    return loaded
                }

                for rule in matchingRules {
                    let ruleAttributes = Self.attributeDependentFields.contains(rule.field) ? try attributes() : [:]
                    guard try matches(entry: entry, attributes: ruleAttributes, rule: rule, behavior: behavior) else {
                        return descendControl
                    }
                }

                let item = try makeResultItem(
                    for: entry,
                    attributes: attributes(),
                    preview: preview,
                    highlight: highlight,
                    matchReasons: matchReasons
                )
                guard behavior.allows(item: item) else {
                    return descendControl
                }
                return collector.append(item) == .reachedLimit ? .stop : descendControl
            } catch {
                return descendControl
            }
        }

        var walkRoots = request.rootPaths
        if let catalogPlan {
            guard let fallbackRoots = runCatalogSearch(
                catalogPlan,
                request: request,
                behavior: behavior,
                specialFolderPlanning: specialFolderPlanning,
                evaluate: evaluate
            ) else {
                return collector.result()
            }
            walkRoots = Self.removingNestedPaths(catalogPlan.walkRoots + fallbackRoots)
        }

        guard walkRoots.isEmpty == false, Task.isCancelled == false else {
            return collector.result()
        }

        let plan = SearchPlan(
            rootPaths: walkRoots,
            rootGroup: .all([]),
            excludedPathFragments: [],
            providerKind: .local,
            shouldScanContents: rules.contains(where: { $0.field == .textContent }),
            includedPathRoots: specialFolderPlanning.includedPathRoots,
            specialFolderExclusions: specialFolderPlanning.specialFolderExclusions,
            slowSearchPaths: specialFolderPlanning.slowSearchPaths
        )
        do {
            try walker.walk(plan: plan, includeHiddenFiles: behavior.includeInvisibleItems, visit: evaluate)
            return collector.result()
        } catch {
            return SearchExecutionResult(title: title, items: [])
        }
    }

    // MARK: - 卷目录搜索

    /// 以整个卷为搜索根、且至少有一条规则要求名称包含某段文字时，用 searchfs 在卷目录中按名称预筛选，
    /// 代替逐个目录遍历；候选项仍按完整规则复核。不满足条件的根目录照常遍历
    private func catalogSearchPlan(
        request: SearchRequest,
        rules: [SearchRuleSelection],
        behavior: SearchRuleExecutionBehavior,
        specialFolderPlanning: SpecialFolderPlanningResult
    ) -> CatalogSearchPlan? {
        // 深度限制依赖遍历时逐层剪枝，卷目录搜索无法提前排除深层目录
        guard let catalogSearcher,
              behavior.maximumFolderDepth == nil,
              let nameFragment = Self.catalogNameFragment(for: rules, diacriticsSensitive: behavior.diacriticsSensitive) else {
            return nil
        }

        let mountPoints = Set(catalogSearcher.mountPoints().map(Self.trimmingTrailingSlash))
        var targets: [CatalogSearchTarget] = []
        var walkRoots: [String] = []

        for rootPath in request.rootPaths {
            let volumePath = Self.trimmingTrailingSlash(rootPath)
            // Data 卷上的条目经固件链接映射到 /Users 等位置，fsgetpath 返回的是映射后的路径，不在 Data 卷挂载点之下
            guard mountPoints.contains(volumePath), volumePath != Self.dataVolumePath else {
                walkRoots.append(rootPath)
                continue
            }

            var rootTargets = [CatalogSearchTarget(volumePath: volumePath, scopeRoot: rootPath, fallbackRoot: rootPath)]
            if volumePath == "/", mountPoints.contains(Self.dataVolumePath) {
                // 启动卷的用户数据在 Data 卷上。只有遍历时也跳过 /System/Volumes/Data（同一文件不会再以该前缀出现），
                // 按固件链接路径返回的 Data 卷结果才与遍历等价
                guard Self.isExcluded(Self.dataVolumePath, by: request.excludedPaths, rootPath: rootPath) else {
                    walkRoots.append(rootPath)
                    continue
                }
                rootTargets.append(CatalogSearchTarget(volumePath: Self.dataVolumePath, scopeRoot: rootPath, fallbackRoot: rootPath))
            }

            // searchfs 不跨越挂载点，遍历会进入的嵌套卷需要单独搜索
            for mountPoint in mountPoints.sorted()
            where mountPoint != Self.dataVolumePath && Self.isStrictDescendant(mountPoint, of: volumePath) {
                guard Self.isExcluded(mountPoint, by: request.excludedPaths, rootPath: rootPath) == false,
                      specialFolderPlanning.allows(path: mountPoint),
                      behavior.includeInvisibleItems || Self.hasHiddenComponent(mountPoint, below: rootPath) == false else {
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
    private func runCatalogSearch(
        _ plan: CatalogSearchPlan,
        request: SearchRequest,
        behavior: SearchRuleExecutionBehavior,
        specialFolderPlanning: SpecialFolderPlanningResult,
        evaluate: @escaping @Sendable (DirectoryEntry) -> DirectoryWalkControl
    ) -> [String]? {
        guard let catalogSearcher, Task.isCancelled == false else {
            return nil
        }

        let state = CatalogSearchState()
        let group = DispatchGroup()
        for target in plan.targets {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let scopePrefix = Self.directoryPrefix(target.scopeRoot)
                do {
                    try catalogSearcher.search(
                        volumePath: target.volumePath,
                        nameFragment: plan.nameFragment,
                        shouldStop: { state.isStopped }
                    ) { matches in
                        for match in matches {
                            guard state.isStopped == false else {
                                return
                            }
                            // 与遍历保持一致：只要搜索根之下的条目，跳过特殊文件夹与隐藏目录中的内容
                            guard match.path.utf8.count > scopePrefix.utf8.count, match.path.hasPrefix(scopePrefix) else {
                                continue
                            }
                            let rootPath = Self.rootPath(containing: match.path, in: request.rootPaths)
                            guard specialFolderPlanning.allows(path: match.path),
                                  behavior.includeInvisibleItems || Self.hasHiddenComponent(match.path, below: rootPath) == false else {
                                continue
                            }
                            let entry = DirectoryEntry(
                                path: match.path,
                                isDirectory: match.isDirectory,
                                isHidden: (match.path as NSString).lastPathComponent.hasPrefix(".")
                            )
                            if evaluate(entry) == .stop {
                                state.stop()
                            }
                        }
                    }
                } catch {
                    // 已回调的结果保留，整个卷改为遍历，重复项由结果汇总去重
                    state.recordFailure(fallbackRoot: target.fallbackRoot)
                }
            }
        }

        // 搜索线程不在 Task 上下文中，取消状态由调用线程轮询后转发
        while group.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if Task.isCancelled {
                state.stop()
            }
        }

        guard state.isStopped == false, Task.isCancelled == false else {
            return nil
        }
        return state.fallbackRoots
    }

    /// 从名称类规则中取一段名称必然包含的文字（规则之间是“且”关系，任取一条都成立），取最长的一段以减少候选项
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

    /// searchfs 按卷自身的规则（分解为 NFD 后折叠大小写）做子串匹配，并不忽略变音符号。
    /// 忽略变音符号时，规则里带变音符号的字符在名称中可能是另一种写法，以它们为界切开；
    /// 大小写映射会改变长度的字符（如 ß、İ）在两边的折叠规则不一致，同样切开
    private static func catalogSafeRuns(of value: String, diacriticsSensitive: Bool) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in value {
            let text = String(character)
            let scalarCount = text.unicodeScalars.count
            let isSafe = (diacriticsSensitive || text.folding(options: .diacriticInsensitive, locale: nil) == text)
                && text.lowercased().unicodeScalars.count == scalarCount
                && text.uppercased().unicodeScalars.count == scalarCount
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

    private static let dataVolumePath = "/System/Volumes/Data"

    private static func trimmingTrailingSlash(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func directoryPrefix(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    private static func isStrictDescendant(_ path: String, of ancestor: String) -> Bool {
        path != ancestor && path.hasPrefix(directoryPrefix(ancestor))
    }

    /// 遍历不会进入名称以 “.” 开头的目录，卷目录搜索的结果需要按路径中搜索根以下的每一级补做同样的判断
    private static func hasHiddenComponent(_ path: String, below rootPath: String) -> Bool {
        let prefix = directoryPrefix(rootPath)
        guard path.hasPrefix(prefix) else {
            return false
        }
        return path.dropFirst(prefix.count).split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// 去掉重复和已被其他根目录覆盖的路径，避免同一棵子树被遍历两次
    private static func removingNestedPaths(_ paths: [String]) -> [String] {
        var result: [String] = []
        for path in paths where paths.contains(where: { isStrictDescendant(path, of: trimmingTrailingSlash($0)) }) == false {
            if result.contains(path) == false {
                result.append(path)
            }
        }
        return result
    }

    private func executeSpotlightSearchIfPossible(
        request: SearchRequest,
        rules: [SearchRuleSelection],
        specialFolderPlanning: SpecialFolderPlanningResult,
        behavior: SearchRuleExecutionBehavior,
        highlight: (kind: SearchResultHighlightKind, query: String)?,
        matchReasons: MatchReasons
    ) -> [SearchResultItem]? {
        var paths = Set<String>()
        for rootPath in request.rootPaths {
            guard let rootPaths = try? spotlightSearchService.search(rootPath: rootPath, rules: request.rules) else {
                return nil
            }
            paths.formUnion(rootPaths)
        }

        let uniquePaths = paths.sorted()
        guard Task.isCancelled == false else {
            return nil
        }
        let preview = request.rules.first?.value ?? ""

        return uniquePaths.compactMap { path in
            let rootPath = Self.rootPath(containing: path, in: request.rootPaths)
            guard specialFolderPlanning.allows(path: path),
                  Self.isExcluded(path, by: request.excludedPaths, rootPath: rootPath) == false else {
                return nil
            }

            guard FileManager.default.fileExists(atPath: path),
                  let attributes = try? provider.attributesOfItem(atPath: path) else {
                return nil
            }

            let entry = DirectoryEntry(
                path: path,
                isDirectory: attributes[.type] as? FileAttributeType == .typeDirectory,
                isHidden: (path as NSString).lastPathComponent.hasPrefix(".")
            )

            guard behavior.allows(entry: entry, rootPath: rootPath) else {
                return nil
            }

            do {
                // Spotlight 查询是不区分大小写的近似结果，这里按完整规则复核；
                // 文本内容由 Spotlight 索引判定（可覆盖 PDF 等非纯文本格式），不再重复读取文件
                guard try rules.allSatisfy({ rule in
                    if rule.field == .textContent { return true }
                    return try matches(entry: entry, attributes: attributes, rule: rule, behavior: behavior)
                }) else {
                    return nil
                }
                return try makeResultItem(
                    for: entry,
                    attributes: attributes,
                    preview: preview,
                    highlight: highlight,
                    matchReasons: matchReasons
                )
            } catch {
                return nil
            }
        }
    }

    /// 匹配时反复用到的规则值只规范化一次：去掉首尾空白，扩展名再去掉首尾的 “.”
    private static func preparedRules(_ rules: [SearchRuleSelection]) -> [SearchRuleSelection] {
        rules.map { rule in
            var prepared = rule
            prepared.value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if rule.field == .extensionName {
                prepared.value = prepared.value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
            return prepared
        }
    }

    /// 需要读取 attributesOfItem 结果才能判定的字段
    private static let attributeDependentFields: Set<SearchRuleField> = [
        .lastModifiedDate, .createdDate, .fileSize, .kind, .script
    ]

    private static func orderedByEvaluationCost(_ rules: [SearchRuleSelection]) -> [SearchRuleSelection] {
        func cost(of field: SearchRuleField) -> Int {
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

        return rules.enumerated()
            .sorted { (cost(of: $0.element.field), $0.offset) < (cost(of: $1.element.field), $1.offset) }
            .map(\.element)
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

    /// 排除路径不作用于它所包含的搜索根之内：例如“所有磁盘”既排除 /Volumes，又把各外置卷作为搜索根
    static func isExcluded(_ path: String, by excludedPaths: [String], rootPath: String) -> Bool {
        excludedPaths.contains { isSameOrDescendant(path, of: $0) && isSameOrDescendant(rootPath, of: $0) == false }
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
        // 规则值已在 preparedRules 中规范化
        guard rule.value.isEmpty == false || SearchRuleExecutionBehavior.globalFields.contains(rule.field) else {
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

            let data = try provider.contentsOfFile(atPath: entry.path)
            return try contentMatcher.matches(
                data: data,
                rule: rule,
                compareOptions: behavior.stringCompareOptions,
                caseSensitive: behavior.caseSensitive
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

    private func makeResultItem(
        for entry: DirectoryEntry,
        attributes: [FileAttributeKey: Any],
        preview: String,
        highlight: (kind: SearchResultHighlightKind, query: String)?,
        matchReasons: MatchReasons
    ) throws -> SearchResultItem {
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
            matchReason: matchReasons.reason(isDirectory: entry.isDirectory),
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

    /// 每次搜索只查一次本地化文案：L10n 每次调用都会重新加载语言包，不适合在遍历中逐项调用
    fileprivate struct MatchReasons: Sendable {
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

    private func matchString(
        _ candidate: String,
        using rule: SearchRuleSelection,
        behavior: SearchRuleExecutionBehavior
    ) -> Bool {
        let value = rule.value
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
            return matchRegex(candidate, pattern: wildcardPattern(from: value), behavior: behavior)
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
            return matchRegex(candidate, pattern: value, behavior: behavior)
        case .doesNotMatchRegex:
            return matchRegex(candidate, pattern: value, behavior: behavior) == false
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
        return matchRegex(foldedCandidate, pattern: pattern, behavior: behavior)
    }

    private func compareKind(
        entry: DirectoryEntry,
        attributes: [FileAttributeKey: Any],
        using rule: SearchRuleSelection
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

    private func matchRegex(_ candidate: String, pattern: String, behavior: SearchRuleExecutionBehavior) -> Bool {
        guard let regex = behavior.regexCache.regex(for: pattern, caseSensitive: behavior.caseSensitive) else {
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

/// 多个卷并发搜索时共享的停止标志与失败记录
private final class CatalogSearchState: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var failedRoots: [String] = []

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    var fallbackRoots: [String] {
        lock.lock()
        defer { lock.unlock() }
        return failedRoots
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    func recordFailure(fallbackRoot: String) {
        lock.lock()
        failedRoots.append(fallbackRoot)
        lock.unlock()
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
    let limitAmount: Int?
    /// 同一次搜索内复用编译好的正则，遍历时每个条目都可能用到
    let regexCache = RegexCache()

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

private final class RegexCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: NSRegularExpression?] = [:]

    func regex(for pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
        let key = (caseSensitive ? "1" : "0") + pattern
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] {
            return cached
        }
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        storage[key] = regex
        return regex
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
    private let limit: Int?
    private let onProgress: (@Sendable (SearchExecutionProgress) -> Void)?
    private var items: [SearchResultItem] = []
    private var seenPaths = Set<String>()
    private var lastProgressTime: TimeInterval?

    init(title: String, limit: Int?, onProgress: (@Sendable (SearchExecutionProgress) -> Void)?) {
        self.title = title
        self.limit = limit.flatMap { $0 > 0 ? $0 : nil }
        self.onProgress = onProgress
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return items.isEmpty
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
        if let onProgress, reachedLimitLocked || lastProgressTime.map({ now - $0 >= Self.progressInterval }) ?? true {
            lastProgressTime = now
            onProgress(.init(title: title, items: items, matchedCount: items.count))
        }
        return reachedLimitLocked ? .reachedLimit : .appended
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

extension SearchExecutor {
    /// 判断是否位于某个包内：除最后一级外，任一级目录名带包扩展名即可
    static func isInsidePackageContents(_ path: String) -> Bool {
        (path as NSString).pathComponents.dropLast().contains(where: isPackagePath)
    }
}

private extension SearchExecutor {
    static func isInsidePackageContents(_ path: String, relativeTo rootPath: String) -> Bool {
        let rootComponentCount = (rootPath as NSString).pathComponents.count
        return (path as NSString).pathComponents
            .dropFirst(rootComponentCount)
            .dropLast()
            .contains(where: isPackagePath)
    }
}
