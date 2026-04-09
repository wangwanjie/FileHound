import Foundation

struct SearchRequest: Sendable {
    let scopeDescription: String
    let rootPath: String
    let query: SearchRuleSelection
}

@MainActor
final class SearchWorkflowController {
    var onStateChange: ((SearchWindowState) -> Void)?
    var onResults: ((String, [SearchResultItem]) -> Void)?

    private var searchTask: Task<Void, Never>?

    func start(request: SearchRequest) {
        cancel()
        onStateChange?(.init(phase: .searching(scopeDescription: request.scopeDescription, matchCount: 0)))

        searchTask = Task { [weak self] in
            guard let self else { return }

            if ProcessInfo.processInfo.arguments.contains("--fixture-delayed-search") {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                let items = self.fixtureItems()
                self.onResults?("Name contains \(request.query.value)", items)
                self.onStateChange?(.init(phase: .editing(matchCount: items.count)))
                return
            }

            let items = await self.performSearch(request: request)
            if Task.isCancelled { return }
            self.onResults?("\(request.query.field.rawValue) \(request.query.operator.rawValue) \(request.query.value)", items)
            self.onStateChange?(.init(phase: .editing(matchCount: items.count)))
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

    private func performSearch(request: SearchRequest) async -> [SearchResultItem] {
        let walker = DirectoryWalker()
        let provider = LocalFilesystemProvider()
        let metadataEvaluator = MetadataEvaluator()
        let contentMatcher = ContentMatcher()

        let plan = SearchPlan(
            rootPaths: [request.rootPath],
            rootGroup: .all([]),
            excludedPathFragments: [],
            providerKind: .local,
            shouldScanContents: request.query.field == .textContent
        )

        do {
            let entries = try walker.walk(plan: plan, includeHiddenFiles: true)
            let filtered = try entries.filter { entry in
                if Task.isCancelled { return false }

                switch request.query.field {
                case .name:
                    return metadataEvaluator.matchesName(entry, fragment: request.query.value)
                case .path:
                    return metadataEvaluator.matchesPath(entry, fragment: request.query.value)
                case .textContent:
                    guard entry.isDirectory == false else { return false }
                    let data = try provider.contentsOfFile(atPath: entry.path)
                    let rule: QueryRule = request.query.operator == .matchesRegex ? .contentMatchesRegex(request.query.value) : .contentContains(request.query.value)
                    return try contentMatcher.matches(data: data, query: rule)
                default:
                    return entry.lastPathComponent.localizedCaseInsensitiveContains(request.query.value)
                }
            }

            return try filtered.map { entry in
                let attributes = try provider.attributesOfItem(atPath: entry.path)
                return SearchResultItem(
                    path: entry.path,
                    matchReason: request.query.field == .textContent ? "内容命中" : "名称命中",
                    previewSnippet: request.query.value,
                    kind: entry.isDirectory ? "Folder" : "Document",
                    modifiedText: Self.displayModifiedDate(attributes: attributes),
                    sizeText: Self.displaySize(attributes: attributes),
                    isInvisible: entry.isHidden,
                    isPackage: URL(fileURLWithPath: entry.path).pathExtension == "app"
                )
            }
        } catch {
            return []
        }
    }

    private static func displayModifiedDate(attributes: [FileAttributeKey: Any]) -> String {
        guard let date = attributes[.modificationDate] as? Date else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d, h:mm:ss a"
        return formatter.string(from: date)
    }

    private static func displaySize(attributes: [FileAttributeKey: Any]) -> String {
        guard let size = attributes[.size] as? NSNumber else {
            return ""
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size.int64Value)
    }
}
