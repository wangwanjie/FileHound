import Foundation

struct SearchRequest: Sendable {
    let scopeDescription: String
    let rootPath: String
    let rules: [SearchRuleSelection]

    init(scopeDescription: String, rootPath: String, rules: [SearchRuleSelection]) {
        self.scopeDescription = scopeDescription
        self.rootPath = rootPath
        self.rules = rules.isEmpty ? [SearchRuleSelection()] : rules
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

    init(executor: SearchExecutor = SearchExecutor()) {
        self.executor = executor
    }

    func start(
        request: SearchRequest,
        preferences: SearchExecutionPreferences = SearchExecutionPreferences()
    ) {
        cancel()
        latestMatchCount = 0
        latestItems = []
        latestTitle = request.queryTitle
        latestScopeDescription = request.scopeDescription
        onStateChange?(.init(phase: .searching(scopeDescription: request.scopeDescription, matchCount: 0)))

        searchTask = Task(priority: .userInitiated) { [weak self, executor] in
            guard let self else { return }

            let emitProgress: @MainActor (SearchExecutionProgress) -> Void = { progress in
                guard Task.isCancelled == false else {
                    return
                }

                self.latestMatchCount = progress.matchedCount
                self.latestItems = progress.items
                self.latestTitle = progress.title
                self.onStateChange?(.init(
                    phase: .searching(
                        scopeDescription: request.scopeDescription,
                        matchCount: progress.matchedCount
                    )
                ))

                if preferences.showResultsEarly, progress.items.isEmpty == false {
                    self.onResults?(progress.title, progress.items)
                }
            }

            if ProcessInfo.processInfo.arguments.contains("--fixture-delayed-search") {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                let items = self.fixtureItems()
                await MainActor.run {
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
                if result.items.isEmpty == false {
                    self.onResults?(result.title, result.items)
                }
                self.onStateChange?(.init(phase: .idle(matchCount: result.items.count)))
            }
        }
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        onStateChange?(.init(phase: .editing(matchCount: latestMatchCount)))
    }

    func fixtureItems() -> [SearchResultItem] {
        [
            SearchResultItem(path: "/tmp/report.txt", matchReason: "内容命中", previewSnippet: "report"),
            SearchResultItem(path: "/tmp/archive.txt", matchReason: "名称命中", previewSnippet: "archive"),
            SearchResultItem(path: "/tmp/report", matchReason: "名称命中", previewSnippet: "lookin")
        ]
    }
}
