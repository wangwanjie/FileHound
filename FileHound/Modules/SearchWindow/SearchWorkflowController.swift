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
    /// 当前搜索的取消标志：搜索在专用线程上执行，取消 Task 传递不过去，停止时直接置位
    private var searchCancellation: SearchCancellationToken?
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

        let cancellation = SearchCancellationToken()
        searchCancellation = cancellation
        // 进度在后台按结果数递增的顺序产生，但每次回主线程都是独立的 Task，到达顺序不保证；
        // 用递增序号丢弃晚到的旧快照，避免界面上的结果数回退
        let progressOrder = ProgressOrder()

        searchTask = Task(priority: .userInitiated) { [weak self, executor] in
            guard let self else { return }

            let emitProgress: @MainActor (SearchExecutionProgress, Int) -> Void = { progress, sequence in
                guard self.generation == searchGeneration, progressOrder.acceptOnMainActor(sequence) else {
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
                    ), progressOrder.next())
                }

                await MainActor.run {
                    guard self.finish(searchGeneration) else { return }
                    self.onResults?(request.queryTitle, partialItems)
                    self.onStateChange?(.init(phase: .idle(matchCount: partialItems.count)))
                }
                return
            }

            let options = SearchExecutionOptions(includeSpotlightResults: preferences.includeSpotlightResults)
            let result = await withTaskCancellationHandler {
                await Self.runOnSearchThread {
                    executor.executeStreaming(request: request, options: options, cancellation: cancellation) { progress in
                        // 序号在结果汇总的锁内取得，与进度产生的顺序一致
                        let sequence = progressOrder.next()
                        Task { @MainActor in
                            emitProgress(progress, sequence)
                        }
                    }
                }
            } onCancel: {
                cancellation.cancel()
            }
            if Task.isCancelled || cancellation.isCancelled {
                return
            }
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

    /// executeStreaming 会阻塞调用线程（内部等待遍历线程、searchfs 与 mdfind），放在 Swift 并发的协作线程池里，
    /// 多个窗口同时搜索时会占满线程池；每次搜索改用一条专用线程，结束后经 continuation 回到异步上下文
    private static func runOnSearchThread(
        _ work: @escaping @Sendable () -> SearchExecutionResult
    ) async -> SearchExecutionResult {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: work())
            }
            thread.name = "FileHound.Search"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        searchCancellation?.cancel()
        searchCancellation = nil
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

/// 为一次搜索的进度快照编号，主线程只接受比已展示的更新的快照
private final class ProgressOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0
    private var delivered = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        issued += 1
        return issued
    }

    /// 在主线程调用：序号比已展示的旧时返回 false
    func acceptOnMainActor(_ sequence: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard sequence > delivered else {
            return false
        }
        delivered = sequence
        return true
    }
}
