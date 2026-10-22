import Foundation

/// 预留给“以管理员权限搜索”的文件访问实现（配合 FileHoundHelper）。目前只是骨架，行为与本地访问相同，尚未接入搜索链路
struct PrivilegedFilesystemProvider: FilesystemAccessProviding, Sendable {
    init() {}

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    func listDirectory(atPath path: String) throws -> [DirectoryListingItem] {
        try BulkDirectoryLister.list(atPath: path)
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }

    func contentsOfFile(atPath path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
    }
}
