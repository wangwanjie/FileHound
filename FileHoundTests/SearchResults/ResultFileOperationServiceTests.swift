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
    func trashesAndDeletesFiles() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("trash-me.txt", contents: "hello")
            try builder.file("delete-me.txt", contents: "bye")
        }

        let service = ResultFileOperationService()
        let trashURL = URL(fileURLWithPath: fixture.path).appendingPathComponent("trash-me.txt")
        let deleteURL = URL(fileURLWithPath: fixture.path).appendingPathComponent("delete-me.txt")

        let trashedURLs = try service.moveToTrash(urls: [trashURL])
        #expect(trashedURLs.count == 1)
        #expect(FileManager.default.fileExists(atPath: trashURL.path) == false)

        try service.deleteImmediately(urls: [deleteURL])
        #expect(FileManager.default.fileExists(atPath: deleteURL.path) == false)
    }
}
