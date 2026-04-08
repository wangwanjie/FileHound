import Foundation

final class SearchSession: Sendable {
    func runPreview(paths: [String], contentNeedle: String) async throws -> SearchSessionSummary {
        let results = paths.map { path in
            SearchResultItem(
                id: UUID(),
                path: path,
                matchReason: "内容命中",
                previewSnippet: contentNeedle
            )
        }

        return SearchSessionSummary(results: results, isCancelled: false)
    }
}
