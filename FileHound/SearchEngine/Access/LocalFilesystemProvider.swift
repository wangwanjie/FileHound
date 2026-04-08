import Foundation

struct LocalFilesystemProvider: FilesystemAccessProviding, Sendable {
    let kind: ProviderKind = .local

    init() {}

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }

    func contentsOfFile(atPath path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }
}
