import Foundation

enum SearchResultHighlightKind: Equatable, Hashable, Sendable {
    case name
    case extensionName
}

struct SearchResultItem: Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let path: String
    let matchReason: String
    let previewSnippet: String?
    let highlightKind: SearchResultHighlightKind?
    let highlightQuery: String?
    let kind: String
    let modifiedText: String
    let createdText: String
    let lastOpenedText: String
    let addedText: String
    let sizeText: String
    let tagsText: String
    let enclosingFolder: String
    let isInvisible: Bool
    let isPackage: Bool
    let isTrashed: Bool
    let modifiedDate: Date?
    let createdDate: Date?
    let lastOpenedDate: Date?
    let addedDate: Date?
    let sizeBytes: Int64?
    let tags: [String]

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    func withUpdatedPath(_ newPath: String) -> SearchResultItem {
        SearchResultItem(
            id: id,
            path: newPath,
            matchReason: matchReason,
            previewSnippet: previewSnippet,
            highlightKind: highlightKind,
            highlightQuery: highlightQuery,
            kind: kind,
            modifiedText: modifiedText,
            createdText: createdText,
            lastOpenedText: lastOpenedText,
            addedText: addedText,
            sizeText: sizeText,
            tagsText: tagsText,
            enclosingFolder: URL(fileURLWithPath: newPath).deletingLastPathComponent().path,
            isInvisible: isInvisible,
            isPackage: isPackage,
            isTrashed: isTrashed,
            modifiedDate: modifiedDate,
            createdDate: createdDate,
            lastOpenedDate: lastOpenedDate,
            addedDate: addedDate,
            sizeBytes: sizeBytes,
            tags: tags
        )
    }

    init(
        id: UUID = UUID(),
        path: String,
        matchReason: String,
        previewSnippet: String?,
        highlightKind: SearchResultHighlightKind? = nil,
        highlightQuery: String? = nil,
        kind: String = "",
        modifiedText: String = "",
        createdText: String = "",
        lastOpenedText: String = "",
        addedText: String = "",
        sizeText: String = "",
        tagsText: String = "",
        enclosingFolder: String = "",
        isInvisible: Bool = false,
        isPackage: Bool = false,
        isTrashed: Bool = false,
        modifiedDate: Date? = nil,
        createdDate: Date? = nil,
        lastOpenedDate: Date? = nil,
        addedDate: Date? = nil,
        sizeBytes: Int64? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.path = path
        self.matchReason = matchReason
        self.previewSnippet = previewSnippet
        self.highlightKind = highlightKind
        self.highlightQuery = highlightQuery
        self.kind = kind
        self.modifiedText = modifiedText
        self.createdText = createdText
        self.lastOpenedText = lastOpenedText
        self.addedText = addedText
        self.sizeText = sizeText
        self.tagsText = tagsText
        self.enclosingFolder = enclosingFolder
        self.isInvisible = isInvisible
        self.isPackage = isPackage
        self.isTrashed = isTrashed
        self.modifiedDate = modifiedDate
        self.createdDate = createdDate
        self.lastOpenedDate = lastOpenedDate
        self.addedDate = addedDate
        self.sizeBytes = sizeBytes
        self.tags = tags
    }
}

struct SearchSessionSummary: Equatable, Sendable {
    let results: [SearchResultItem]
    let isCancelled: Bool
}
