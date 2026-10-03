import Foundation

struct SearchRequest: Sendable {
    let scopeDescription: String
    let rootPaths: [String]
    /// 遍历时整棵跳过的路径（例如从 "/" 搜索时的 /Volumes、/System/Volumes）
    let excludedPaths: [String]
    let rules: [SearchRuleSelection]

    var rootPath: String {
        rootPaths.first ?? "/"
    }

    init(
        scopeDescription: String,
        rootPaths: [String],
        excludedPaths: [String] = [],
        rules: [SearchRuleSelection]
    ) {
        self.scopeDescription = scopeDescription
        self.rootPaths = rootPaths
        self.excludedPaths = excludedPaths
        self.rules = rules.isEmpty ? [SearchRuleSelection()] : rules
    }

    init(scopeDescription: String, rootPath: String, rules: [SearchRuleSelection]) {
        self.init(scopeDescription: scopeDescription, rootPaths: [rootPath], rules: rules)
    }

    init(scopeDescription: String, rootPath: String, query: SearchRuleSelection) {
        self.init(scopeDescription: scopeDescription, rootPath: rootPath, rules: [query])
    }

    var queryTitle: String {
        rules
            .map(\.summaryText)
            .joined(separator: " and ")
    }
}

final class SearchWorkflowController {
    var onStateChange: ((SearchWindowState) -> Void)?
    var onResults: ((String, [SearchResultItem]) -> Void)?

    private var searchTask: Task<Void, Never>?
    private let executor: SearchExecutor
    private var latestMatchCount = 0
    private var latestItems: [SearchResultItem] = []
    private var latestTitle = ""
    private var latestScopeDescription = ""
    /// 用户在搜索中点击「显示结果」后置为 true：即使未开启「提前显示搜索结果」，本次搜索后续进度也持续推送结果
    private var revealsResultsForCurrentSearch = false
    /// 每次开始、取消或完成搜索时递增；进度回调异步回到主线程，用它丢弃已结束搜索的迟到进度
    private var generation = 0

    init(executor: SearchExecutor = SearchExecutor()) {
        self.executor = executor
    }

    func start(
        request: SearchRequest,
        preferences: SearchExecutionPreferences = SearchExecutionPreferences()
    ) {
        cancel()
        generation += 1
        let searchGeneration = generation
        latestMatchCount = 0
        latestItems = []
        latestTitle = request.queryTitle
        latestScopeDescription = request.scopeDescription
        revealsResultsForCurrentSearch = false
        onStateChange?(.init(phase: .searching(scopeDescription: request.scopeDescription, matchCount: 0)))

        searchTask = Task(priority: .userInitiated) { [weak self, executor] in
            guard let self else { return }

            let emitProgress: @MainActor (SearchExecutionProgress) -> Void = { progress in
                guard self.generation == searchGeneration else {
                    return
                }

                self.deliverProgress(
                    progress,
                    scopeDescription: request.scopeDescription,
                    showResultsEarly: preferences.showResultsEarly
                )
            }

            if ProcessInfo.processInfo.arguments.contains("--fixture-delayed-search") {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                let items = self.fixtureItems()
                await MainActor.run {
                    guard self.finish(searchGeneration) else { return }
                    self.onResults?("Name contains \(request.rules.first?.value ?? "")", items)
                    self.onStateChange?(.init(phase: .idle(matchCount: items.count)))
                }
                return
            }

            if ProcessInfo.processInfo.arguments.contains("--fixture-streaming-search") ||
                ProcessInfo.processInfo.arguments.contains("--fixture-streaming-search-slow") {
                let items = self.fixtureItems()
                var partialItems: [SearchResultItem] = []
                let streamingDelayNanoseconds: UInt64 =
                    ProcessInfo.processInfo.arguments.contains("--fixture-streaming-search-slow")
                    ? 1_000_000_000
                    : 400_000_000

                for item in items {
                    try? await Task.sleep(nanoseconds: streamingDelayNanoseconds)
                    if Task.isCancelled { return }
                    partialItems.append(item)
                    await emitProgress(.init(
                        title: request.queryTitle,
                        items: partialItems,
                        matchedCount: partialItems.count
                    ))
                }

                await MainActor.run {
                    guard self.finish(searchGeneration) else { return }
                    self.onResults?(request.queryTitle, partialItems)
                    self.onStateChange?(.init(phase: .idle(matchCount: partialItems.count)))
                }
                return
            }

            let result = executor.executeStreaming(
                request: request,
                options: SearchExecutionOptions(
                    includeSpotlightResults: preferences.includeSpotlightResults
                )
            ) { progress in
                Task { @MainActor in
                    await emitProgress(progress)
                }
            }
            if Task.isCancelled { return }
            await MainActor.run {
                guard self.finish(searchGeneration) else { return }
                if result.items.isEmpty == false {
                    self.onResults?(result.title, result.items)
                }
                self.onStateChange?(.init(phase: .idle(matchCount: result.items.count)))
            }
        }
    }

    @MainActor
    private func deliverProgress(
        _ progress: SearchExecutionProgress,
        scopeDescription: String,
        showResultsEarly: Bool
    ) {
        latestMatchCount = progress.matchedCount
        latestItems = progress.items
        latestTitle = progress.title
        onStateChange?(.init(
            phase: .searching(
                scopeDescription: scopeDescription,
                matchCount: progress.matchedCount
            )
        ))

        if showResultsEarly || revealsResultsForCurrentSearch,
           progress.items.isEmpty == false {
            onResults?(progress.title, progress.items)
        }
    }

    /// 搜索进行中立即推送已找到的结果，并让本次搜索剩余的进度继续刷新结果页
    func revealResults() {
        revealsResultsForCurrentSearch = true
        guard latestItems.isEmpty == false else {
            return
        }
        onResults?(latestTitle, latestItems)
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        generation += 1
        onStateChange?(.init(phase: .editing(matchCount: latestMatchCount)))
    }

    /// 标记该次搜索已结束，之后迟到的进度不再生效；返回 false 表示它已被取消或被新搜索取代
    private func finish(_ searchGeneration: Int) -> Bool {
        guard generation == searchGeneration else {
            return false
        }
        generation += 1
        return true
    }

    func fixtureItems() -> [SearchResultItem] {
        [
            SearchResultItem(path: "/tmp/report.txt", matchReason: "内容命中", previewSnippet: "report"),
            SearchResultItem(path: "/tmp/archive.txt", matchReason: "名称命中", previewSnippet: "archive"),
            SearchResultItem(path: "/tmp/report", matchReason: "名称命中", previewSnippet: "lookin")
        ]
    }
}

#if DEBUG
extension SearchWorkflowController {
    /// 绕过真实搜索，直接投递一次进度，用于测试搜索中的界面联动
    @MainActor
    func debugDeliverProgress(_ progress: SearchExecutionProgress, scopeDescription: String, showResultsEarly: Bool) {
        deliverProgress(progress, scopeDescription: scopeDescription, showResultsEarly: showResultsEarly)
    }
}
#endif
