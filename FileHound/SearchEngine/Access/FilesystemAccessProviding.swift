import Foundation

/// 目录的一个直接子项：遍历只需要名称、是否为目录与是否不可见
struct DirectoryListingItem: Hashable, Sendable {
    let name: String
    let isDirectory: Bool
    /// 是否带有 UF_HIDDEN 标志（如 ~/Library）；名称以 “.” 开头的不可见项由 isHidden 另行判断
    let hasHiddenFlag: Bool

    init(name: String, isDirectory: Bool, hasHiddenFlag: Bool = false) {
        self.name = name
        self.isDirectory = isDirectory
        self.hasHiddenFlag = hasHiddenFlag
    }

    /// 与访达一致：名称以 “.” 开头或带 UF_HIDDEN 标志的条目都是不可见项目
    var isHidden: Bool {
        hasHiddenFlag || name.hasPrefix(".")
    }
}

protocol FilesystemAccessProviding: Sendable {
    func contentsOfDirectory(atPath path: String) throws -> [String]
    /// 列出目录的直接子项及其类型；读取属性失败的子项会被略过
    func listDirectory(atPath path: String) throws -> [DirectoryListingItem]
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
    func contentsOfFile(atPath path: String) throws -> Data
}

extension FilesystemAccessProviding {
    /// 默认实现逐项读取属性（只按名称判断不可见）；本地文件系统用 getattrlistbulk 批量读取以避免每个子项一次系统调用
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
