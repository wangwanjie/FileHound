import Foundation

protocol FilesystemAccessProviding: Sendable {
    var kind: ProviderKind { get }
    func contentsOfDirectory(atPath path: String) throws -> [String]
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
    func contentsOfFile(atPath path: String) throws -> Data
}
