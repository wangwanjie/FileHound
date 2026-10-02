import Foundation
import Testing
@testable import FileHound

@MainActor
struct DirectoryChangeWatcherTests {
    @Test
    func notifiesWhenItemIsMovedBackIntoWatchedDirectory() async throws {
        let original = try TemporaryFixtureTree.make { builder in
            try builder.file("folder/.keep", contents: "")
        }
        let holding = try TemporaryFixtureTree.make { builder in
            try builder.file("a.txt", contents: "hello")
        }
        let folder = original.rootURL.appendingPathComponent("folder")

        var changeCount = 0
        let watcher = DirectoryChangeWatcher()
        watcher.onChange = { changeCount += 1 }
        watcher.watch(directories: [folder.path])

        // 模拟「放回原处」：文件从别处移回被监听的目录
        try FileManager.default.moveItem(
            at: holding.rootURL.appendingPathComponent("a.txt"),
            to: folder.appendingPathComponent("a.txt")
        )

        for _ in 0..<50 where changeCount == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(changeCount > 0)
    }
}
