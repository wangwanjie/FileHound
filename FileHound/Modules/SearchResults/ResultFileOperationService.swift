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
    /// 把单个文件移到废纸篓并返回其在废纸篓中的位置；可注入以便测试时不碰用户真实的废纸篓
    typealias TrashHandler = (URL) throws -> URL

    private let trashHandler: TrashHandler

    init(trashHandler: @escaping TrashHandler = ResultFileOperationService.trashWithFileManager) {
        self.trashHandler = trashHandler
    }

    static func trashWithFileManager(_ url: URL) throws -> URL {
        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        return trashedURL as URL? ?? url
    }

    func moveToTrash(urls: [URL]) throws -> [URL] {
        try urls.map(trashHandler)
    }

    func deleteImmediately(urls: [URL]) throws {
        try urls.forEach { try FileManager.default.removeItem(at: $0) }
    }

    /// 调用前应先经过 ResultRenameValidator 校验新名称
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

/// 重命名校验：与访达一致，名称不能为空、不能含 "/" 或 ":"（访达中输入的 "/" 在磁盘上存为 ":"，
/// 结果窗口显示的是磁盘上的 POSIX 名称，两者都可能造成歧义，统一拒绝），也不能是 "." / ".."
enum ResultRenameValidationError: LocalizedError, Equatable {
    case empty
    case containsSlash
    case containsColon
    case reservedName
    case tooLong

    var errorDescription: String? {
        switch self {
        case .empty:
            return L10n.string("results.rename.error.empty")
        case .containsSlash:
            return L10n.string("results.rename.error.slash")
        case .containsColon:
            return L10n.string("results.rename.error.colon")
        case .reservedName:
            return L10n.string("results.rename.error.reserved")
        case .tooLong:
            return L10n.string("results.rename.error.too_long")
        }
    }
}

enum ResultRenameValidator {
    /// 校验新名称；返回 nil 表示与原名相同、无需改名
    static func validatedName(_ newName: String, originalName: String) throws -> String? {
        if newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ResultRenameValidationError.empty
        }
        if newName.contains("/") {
            throw ResultRenameValidationError.containsSlash
        }
        if newName.contains(":") {
            throw ResultRenameValidationError.containsColon
        }
        if newName == "." || newName == ".." {
            throw ResultRenameValidationError.reservedName
        }
        // APFS / HFS+ 单个文件名最多 255 个 UTF-16 码元（按 UTF-8 字节数近似校验会误拒中文，这里按 UTF-16 计）
        if newName.utf16.count > 255 {
            throw ResultRenameValidationError.tooLong
        }
        return newName == originalName ? nil : newName
    }
}
