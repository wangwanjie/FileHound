import Foundation

struct TemporaryFixtureTree {
    let rootURL: URL

    var path: String {
        rootURL.path
    }

    static func make(_ build: (inout Builder) throws -> Void) throws -> TemporaryFixtureTree {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var builder = Builder(rootURL: rootURL)
        try build(&builder)
        return TemporaryFixtureTree(rootURL: rootURL)
    }

    struct Builder {
        let rootURL: URL

        mutating func file(_ relativePath: String, contents: String) throws {
            let fileURL = rootURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try contents.data(using: .utf8).unwrap()
            try data.write(to: fileURL)
        }
    }
}

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let value = self else {
            throw FixtureError.unexpectedNil
        }
        return value
    }
}

private enum FixtureError: Error {
    case unexpectedNil
}
