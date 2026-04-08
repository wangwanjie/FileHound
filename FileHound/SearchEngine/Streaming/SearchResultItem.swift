import Foundation

struct SearchResultItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let path: String
    let matchReason: String
    let previewSnippet: String?
}

struct SearchSessionSummary: Equatable, Sendable {
    let results: [SearchResultItem]
    let isCancelled: Bool
}
