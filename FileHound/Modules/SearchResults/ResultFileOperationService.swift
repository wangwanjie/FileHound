import Foundation

protocol ResultFileOperationServing {
    func moveToTrash(urls: [URL]) throws -> [URL]
    func deleteImmediately(urls: [URL]) throws
    func renameItem(at url: URL, to newName: String) throws -> URL
    func createAlias(for url: URL, in destinationFolder: URL) throws -> URL
    func setHidden(_ hidden: Bool, for url: URL) throws -> URL
    func setLocked(_ locked: Bool, for url: URL) throws -> URL
    func setLabel(_ labelNumber: Int, for url: URL) throws -> URL
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
        let aliasURL = Self.availableAliasURL(for: url, in: destinationFolder)
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

    /// Finder 标签编号：0 无、1 灰、2 绿、3 紫、4 蓝、5 黄、6 红、7 橙
    func setLabel(_ labelNumber: Int, for url: URL) throws -> URL {
        var mutableURL = url
        var values = URLResourceValues()
        values.labelNumber = min(max(labelNumber, 0), 7)
        try mutableURL.setResourceValues(values)
        return mutableURL
    }

    /// 与 Finder 一致的替身命名：“名称 alias”，重名时追加序号
    static func availableAliasURL(
        for url: URL,
        in destinationFolder: URL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let baseName = url.lastPathComponent + " alias"
        var candidate = destinationFolder.appendingPathComponent(baseName)
        var index = 2
        while fileExists(candidate.path) {
            candidate = destinationFolder.appendingPathComponent("\(baseName) \(index)")
            index += 1
        }
        return candidate
    }
}

extension ResultFileOperationService: ResultFileOperationServing {}
