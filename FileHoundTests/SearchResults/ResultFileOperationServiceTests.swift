import Foundation
import Testing
@testable import FileHound

struct ResultFileOperationServiceTests {
    @Test
    func renamesAliasesAndTogglesVisibilityAndLockingOnFixtureFiles() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "hello")
        }

        let service = ResultFileOperationService()
        let sourceURL = URL(fileURLWithPath: fixture.path).appendingPathComponent("report.txt")

        let renamedURL = try service.renameItem(at: sourceURL, to: "renamed.txt")
        #expect(renamedURL.lastPathComponent == "renamed.txt")
        #expect(FileManager.default.fileExists(atPath: renamedURL.path))

        let aliasURL = try service.createAlias(for: renamedURL, in: URL(fileURLWithPath: fixture.path))
        #expect(FileManager.default.fileExists(atPath: aliasURL.path))
        #expect(aliasURL.lastPathComponent == "renamed.txt alias")
        let resolvedAlias = try URL(resolvingAliasFileAt: aliasURL)
        #expect(resolvedAlias.resolvingSymlinksInPath().path == renamedURL.resolvingSymlinksInPath().path)
        let secondAliasURL = try service.createAlias(for: renamedURL, in: URL(fileURLWithPath: fixture.path))
        #expect(secondAliasURL.lastPathComponent == "renamed.txt alias 2")

        let redURL = try service.setLabel(6, for: renamedURL)
        let labelValues = try URL(fileURLWithPath: redURL.path).resourceValues(forKeys: [.labelNumberKey])
        #expect(labelValues.labelNumber == 6)
        _ = try service.setLabel(0, for: renamedURL)
        #expect(try URL(fileURLWithPath: renamedURL.path).resourceValues(forKeys: [.labelNumberKey]).labelNumber == 0)

        let hiddenURL = try service.setHidden(true, for: renamedURL)
        let hiddenValues = try hiddenURL.resourceValues(forKeys: Set<URLResourceKey>([.isHiddenKey]))
        #expect(hiddenValues.isHidden == true)

        let visibleURL = try service.setHidden(false, for: hiddenURL)
        let visibleValues = try visibleURL.resourceValues(forKeys: Set<URLResourceKey>([.isHiddenKey]))
        #expect(visibleValues.isHidden == false)

        let lockedURL = try service.setLocked(true, for: visibleURL)
        let lockedValues = try lockedURL.resourceValues(forKeys: Set<URLResourceKey>([.isUserImmutableKey]))
        #expect(lockedValues.isUserImmutable == true)

        let unlockedURL = try service.setLocked(false, for: lockedURL)
        let unlockedValues = try unlockedURL.resourceValues(forKeys: Set<URLResourceKey>([.isUserImmutableKey]))
        #expect(unlockedValues.isUserImmutable == false)
    }

    @Test
    func moveToTrashUsesInjectedTrashHandler() throws {
        // 不碰用户真实的废纸篓：注入假实现，验证每个 URL 都交给它处理并返回其结果
        var trashedPaths: [String] = []
        let service = ResultFileOperationService(trashHandler: { url in
            trashedPaths.append(url.path)
            return URL(fileURLWithPath: "/Trash").appendingPathComponent(url.lastPathComponent)
        })

        let results = try service.moveToTrash(urls: [
            URL(fileURLWithPath: "/tmp/a.txt"),
            URL(fileURLWithPath: "/tmp/b.txt")
        ])

        #expect(trashedPaths == ["/tmp/a.txt", "/tmp/b.txt"])
        #expect(results.map(\.path) == ["/Trash/a.txt", "/Trash/b.txt"])
    }

    @Test
    func moveToTrashPropagatesHandlerErrors() {
        struct TrashFailure: Error {}
        let service = ResultFileOperationService(trashHandler: { _ in throw TrashFailure() })

        #expect(throws: TrashFailure.self) {
            try service.moveToTrash(urls: [URL(fileURLWithPath: "/tmp/a.txt")])
        }
    }

    @Test
    func deletesFilesImmediatelyInsideFixture() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("delete-me.txt", contents: "bye")
        }

        let service = ResultFileOperationService(trashHandler: { _ in
            Issue.record("立即删除不应走废纸篓")
            return URL(fileURLWithPath: "/")
        })
        let deleteURL = URL(fileURLWithPath: fixture.path).appendingPathComponent("delete-me.txt")

        try service.deleteImmediately(urls: [deleteURL])
        #expect(FileManager.default.fileExists(atPath: deleteURL.path) == false)
    }
}
