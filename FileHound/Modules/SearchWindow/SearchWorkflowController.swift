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
}

final class SearchWorkflowController {
    var onStateChange: ((SearchWindowState) -> Void)?
    var onResults: ((String, [SearchResultItem]) -> Void)?

    private var searchTask: Task<Void, Never>?
    private let executor: SearchExecutor

    init(executor: SearchExecutor = SearchExecutor()) {
        self.executor = executor
    }

    func start(request: SearchRequest) {
        cancel()
        onStateChange?(.init(phase: .searching(scopeDescription: request.scopeDescription, matchCount: 0)))

        searchTask = Task(priority: .userInitiated) { [weak self, executor] in
            guard let self else { return }

            if ProcessInfo.processInfo.arguments.contains("--fixture-delayed-search") {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                let items = self.fixtureItems()
                await MainActor.run {
                    self.onResults?("Name contains \(request.rules.first?.value ?? "")", items)
                    self.onStateChange?(.init(phase: .editing(matchCount: items.count)))
                }
                return
            }

            let result = executor.execute(request: request)
            if Task.isCancelled { return }
            await MainActor.run {
                if result.items.isEmpty == false {
                    self.onResults?(result.title, result.items)
                }
                self.onStateChange?(.init(phase: .editing(matchCount: result.items.count)))
            }
        }
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
    }

    func fixtureItems() -> [SearchResultItem] {
        [
            SearchResultItem(path: "/tmp/report.txt", matchReason: "内容命中", previewSnippet: "report"),
            SearchResultItem(path: "/tmp/archive.txt", matchReason: "名称命中", previewSnippet: "archive"),
            SearchResultItem(path: "/tmp/report.lookin", matchReason: "名称命中", previewSnippet: "lookin")
        ]
    }
}
