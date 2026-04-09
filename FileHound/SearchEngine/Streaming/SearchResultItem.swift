import Foundation

struct SearchResultItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let path: String
    let matchReason: String
    let previewSnippet: String?
    let kind: String
    let modifiedText: String
    let sizeText: String
    let isInvisible: Bool
    let isPackage: Bool

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    init(
        id: UUID = UUID(),
        path: String,
        matchReason: String,
        previewSnippet: String?,
        kind: String = "",
        modifiedText: String = "",
        sizeText: String = "",
        isInvisible: Bool = false,
        isPackage: Bool = false
    ) {
        self.id = id
        self.path = path
        self.matchReason = matchReason
        self.previewSnippet = previewSnippet
        self.kind = kind
        self.modifiedText = modifiedText
        self.sizeText = sizeText
        self.isInvisible = isInvisible
        self.isPackage = isPackage
    }
}

struct SearchSessionSummary: Equatable, Sendable {
    let results: [SearchResultItem]
    let isCancelled: Bool
}
