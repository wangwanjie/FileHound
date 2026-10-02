import Foundation

/// 目录的一个直接子项：遍历只需要名称与是否为目录
struct DirectoryListingItem: Hashable, Sendable {
    let name: String
    let isDirectory: Bool
}

protocol FilesystemAccessProviding: Sendable {
    var kind: ProviderKind { get }
    func contentsOfDirectory(atPath path: String) throws -> [String]
    /// 列出目录的直接子项及其类型；读取属性失败的子项会被略过
    func listDirectory(atPath path: String) throws -> [DirectoryListingItem]
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
    func contentsOfFile(atPath path: String) throws -> Data
}

extension FilesystemAccessProviding {
    /// 默认实现逐项读取属性；本地文件系统用 getattrlistbulk 批量读取以避免每个子项一次系统调用
    func listDirectory(atPath path: String) throws -> [DirectoryListingItem] {
        try contentsOfDirectory(atPath: path).compactMap { name in
            let childPath = (path as NSString).appendingPathComponent(name)
            guard let attributes = try? attributesOfItem(atPath: childPath) else {
                return nil
            }
            return DirectoryListingItem(
                name: name,
                isDirectory: attributes[.type] as? FileAttributeType == .typeDirectory
            )
        }
    }
}
