import Foundation

protocol ResultFileOperationServing {
    func moveToTrash(urls: [URL]) throws -> [URL]
    func deleteImmediately(urls: [URL]) throws
    func renameItem(at url: URL, to newName: String) throws -> URL
    func createAlias(for url: URL, in destinationFolder: URL) throws -> URL
    func setHidden(_ hidden: Bool, for url: URL) throws -> URL
    func setLocked(_ locked: Bool, for url: URL) throws -> URL
}

struct ResultFileOperationService {
    func moveToTrash(urls: [URL]) throws -> [URL] {
        try urls.map { url in
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
            return trashedURL as URL? ?? url
        }
    }

    func deleteImmediately(urls: [URL]) throws {
        try urls.forEach { try FileManager.default.removeItem(at: $0) }
    }

    func renameItem(at url: URL, to newName: String) throws -> URL {
        let destinationURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: url, to: destinationURL)
        return destinationURL
    }

    func createAlias(for url: URL, in destinationFolder: URL) throws -> URL {
        let aliasName = url.deletingPathExtension().lastPathComponent + " alias"
        let aliasURL = destinationFolder.appendingPathComponent(aliasName).appendingPathExtension("alias")
        let bookmarkData = try url.bookmarkData(
            options: .suitableForBookmarkFile,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try URL.writeBookmarkData(bookmarkData, to: aliasURL)
        return aliasURL
    }

    func setHidden(_ hidden: Bool, for url: URL) throws -> URL {
        var mutableURL = url
        var values = URLResourceValues()
        values.isHidden = hidden
        try mutableURL.setResourceValues(values)
        return mutableURL
    }

    func setLocked(_ locked: Bool, for url: URL) throws -> URL {
        var mutableURL = url
        var values = URLResourceValues()
        values.isUserImmutable = locked
        try mutableURL.setResourceValues(values)
        return mutableURL
    }
}

extension ResultFileOperationService: ResultFileOperationServing {}
