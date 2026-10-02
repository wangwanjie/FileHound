import Foundation

struct PrivilegedFilesystemProvider: FilesystemAccessProviding, Sendable {
    let kind: ProviderKind = .privileged

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
