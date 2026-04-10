import Foundation

struct SearchResultItem: Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    let path: String
    let matchReason: String
    let previewSnippet: String?
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

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    func withUpdatedPath(_ newPath: String) -> SearchResultItem {
        SearchResultItem(
            id: id,
            path: newPath,
            matchReason: matchReason,
            previewSnippet: previewSnippet,
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
            isTrashed: isTrashed
        )
    }

    init(
        id: UUID = UUID(),
        path: String,
        matchReason: String,
        previewSnippet: String?,
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
        isTrashed: Bool = false
    ) {
        self.id = id
        self.path = path
        self.matchReason = matchReason
        self.previewSnippet = previewSnippet
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
    }
}

struct SearchSessionSummary: Equatable, Sendable {
    let results: [SearchResultItem]
    let isCancelled: Bool
}
