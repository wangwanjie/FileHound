import Foundation
import Testing
@testable import FileHound

struct ResultActionControllerTests {
    @Test
    func renameIsDisabledForMultiSelectionButTrashAndRemoveRemainEnabled() {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "名称命中", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "名称命中", previewSnippet: nil)
        let controller = ResultActionController(
            fileService: StubResultFileOperationService(),
            confirmationPresenter: { _ in true }
        )

        let state = controller.menuState(for: [first, second])

        #expect(state.canRename == false)
        #expect(state.canMoveToTrash == true)
        #expect(state.canRemoveFromResults == true)
    }

    @Test
    func deleteRenameAndRemoveRefreshViewModelImmediately() throws {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "名称命中", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "名称命中", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [first, second]
        let controller = ResultActionController(
            fileService: StubResultFileOperationService(renamedPath: "/tmp/renamed.txt"),
            itemRefresher: { _, _ in nil },
            confirmationPresenter: { _ in true }
        )

        try controller.handleRename(item: second, newName: "renamed.txt", viewModel: viewModel)
        #expect(viewModel.items.map(\.path).contains("/tmp/renamed.txt"))
        #expect(viewModel.items.contains { $0.path == "/tmp/b.txt" } == false)

        try controller.handleDeleteImmediately(items: [first], viewModel: viewModel)
        #expect(viewModel.items.map(\.path) == ["/tmp/renamed.txt"])

        controller.removeFromResults(items: [viewModel.items[0]], viewModel: viewModel)
        #expect(viewModel.items.isEmpty)
    }

    @Test
    func syntheticFolderNodesDisableDestructiveActions() {
        let matched = SearchResultItem(path: "/tmp/demo/a.txt", matchReason: "", previewSnippet: nil)
        let synthetic = SearchResultItem(path: "/tmp/demo", matchReason: "", previewSnippet: nil)
        let controller = ResultActionController(fileService: StubResultFileOperationService(), confirmationPresenter: { _ in true })
        let isMatched: (SearchResultItem) -> Bool = { $0.id == matched.id }

        let matchedState = controller.menuState(for: [matched], isMatchedResult: isMatched)
        #expect(matchedState.canRename && matchedState.canMoveToTrash && matchedState.canRemoveFromResults && matchedState.canModifyAttributes)

        for items in [[synthetic], [matched, synthetic]] {
            let state = controller.menuState(for: items, isMatchedResult: isMatched)
            #expect(state.canRename == false)
            #expect(state.canMoveToTrash == false)
            #expect(state.canRemoveFromResults == false)
            #expect(state.canModifyAttributes == false)
        }
    }

    @Test
    func handlersIgnoreItemsThatAreNotMatchedResults() throws {
        let matched = SearchResultItem(path: "/tmp/demo/a.txt", matchReason: "", previewSnippet: nil)
        // 树视图补出的上级文件夹节点不在视图模型的结果中
        let synthetic = SearchResultItem(path: "/tmp/demo", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [matched]
        let service = RecordingFileService()
        var confirmations: [ResultConfirmationRequest] = []
        let controller = ResultActionController(fileService: service, confirmationPresenter: { request in
            confirmations.append(request)
            return true
        })

        try controller.handleDeleteImmediately(items: [synthetic], viewModel: viewModel)
        try controller.handleMoveToTrash(items: [synthetic], viewModel: viewModel)
        try controller.handleRename(item: synthetic, newName: "other", viewModel: viewModel)
        controller.removeFromResults(items: [synthetic], viewModel: viewModel)

        #expect(confirmations.isEmpty)
        #expect(service.calls.isEmpty)
        #expect(viewModel.items == [matched])
    }

    @Test
    func deleteCancelledByUserLeavesFilesAndResultsUntouched() throws {
        let item = SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [item]
        let service = RecordingFileService()
        var receivedRequest: ResultConfirmationRequest?
        let controller = ResultActionController(fileService: service, confirmationPresenter: { request in
            receivedRequest = request
            return false
        })

        try controller.handleDeleteImmediately(items: [item], viewModel: viewModel)

        #expect(receivedRequest == .deleteImmediately(items: [item]))
        #expect(service.calls.isEmpty)
        #expect(viewModel.items == [item])
    }

    @Test
    func deleteConfirmationNamesSingleItemAndCountsMultipleItems() {
        let first = SearchResultItem(path: "/Users/me/Documents/报告 2026.txt", matchReason: "", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "", previewSnippet: nil)

        let single = ResultConfirmationRequest.deleteImmediately(items: [first]).informativeText
        #expect(single.contains("报告 2026.txt"))
        #expect(single.contains("/Users/me/Documents/报告 2026.txt"))

        let multiple = ResultConfirmationRequest.deleteImmediately(items: [first, second]).informativeText
        #expect(multiple == L10n.format("results.delete.multiple", Int64(2)))
    }

    @Test
    func deletingFolderAlsoRemovesDescendantResults() throws {
        let folder = SearchResultItem(path: "/tmp/demo", matchReason: "", previewSnippet: nil)
        let child = SearchResultItem(path: "/tmp/demo/a.txt", matchReason: "", previewSnippet: nil)
        let sibling = SearchResultItem(path: "/tmp/demo2/b.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [folder, child, sibling]
        let controller = ResultActionController(fileService: RecordingFileService(), confirmationPresenter: { _ in true })

        try controller.handleDeleteImmediately(items: [folder], viewModel: viewModel)

        // 只移除以 "/tmp/demo/" 为前缀的后代，"/tmp/demo2" 不受影响
        #expect(viewModel.items.map(\.path) == ["/tmp/demo2/b.txt"])
    }

    @Test
    func renameValidatesNamesLikeFinder() throws {
        #expect(throws: ResultRenameValidationError.empty) {
            try ResultRenameValidator.validatedName("   ", originalName: "a.txt")
        }
        #expect(throws: ResultRenameValidationError.containsSlash) {
            try ResultRenameValidator.validatedName("a/b.txt", originalName: "a.txt")
        }
        #expect(throws: ResultRenameValidationError.containsColon) {
            try ResultRenameValidator.validatedName("a:b.txt", originalName: "a.txt")
        }
        #expect(throws: ResultRenameValidationError.reservedName) {
            try ResultRenameValidator.validatedName("..", originalName: "a.txt")
        }
        #expect(throws: ResultRenameValidationError.tooLong) {
            try ResultRenameValidator.validatedName(String(repeating: "a", count: 256), originalName: "a.txt")
        }
        #expect(try ResultRenameValidator.validatedName("a.txt", originalName: "a.txt") == nil)
        #expect(try ResultRenameValidator.validatedName("报告 😀.txt", originalName: "a.txt") == "报告 😀.txt")
    }

    @Test
    func invalidOrUnchangedRenameDoesNotTouchFile() throws {
        let item = SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [item]
        let service = RecordingFileService()
        let controller = ResultActionController(fileService: service, confirmationPresenter: { _ in true })

        #expect(throws: ResultRenameValidationError.containsSlash) {
            try controller.handleRename(item: item, newName: "x/y", viewModel: viewModel)
        }
        try controller.handleRename(item: item, newName: "a.txt", viewModel: viewModel)

        #expect(service.calls.isEmpty)
        #expect(viewModel.items == [item])
    }

    @Test
    func renamingFolderRefreshesItemAndRewritesDescendantPaths() throws {
        let folder = SearchResultItem(path: "/tmp/demo", matchReason: "", previewSnippet: nil)
        let child = SearchResultItem(path: "/tmp/demo/sub/a.txt", matchReason: "", previewSnippet: nil)
        let sibling = SearchResultItem(path: "/tmp/demo2/b.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [folder, child, sibling]
        let service = RecordingFileService()
        let controller = ResultActionController(
            fileService: service,
            // 模拟改名为以 "." 开头后文件变为隐藏：改名后应使用刷新得到的属性
            itemRefresher: { item, path in
                SearchResultItem(id: item.id, path: path, matchReason: item.matchReason, previewSnippet: nil, isInvisible: true)
            },
            confirmationPresenter: { _ in true }
        )

        try controller.handleRename(item: folder, newName: ".hidden-demo", viewModel: viewModel)

        #expect(service.calls == ["rename /tmp/demo -> .hidden-demo"])
        #expect(viewModel.items.map(\.path) == ["/tmp/.hidden-demo", "/tmp/.hidden-demo/sub/a.txt", "/tmp/demo2/b.txt"])
        #expect(viewModel.items[0].isInvisible)
        #expect(viewModel.items[0].id == folder.id)
        #expect(viewModel.items[1].id == child.id)
    }
}

/// 记录调用的假文件服务，不触碰真实文件系统
private final class RecordingFileService: ResultFileOperationServing {
    private(set) var calls: [String] = []

    func moveToTrash(urls: [URL]) throws -> [URL] {
        calls.append("trash " + urls.map(\.path).joined(separator: ","))
        return urls
    }

    func deleteImmediately(urls: [URL]) throws {
        calls.append("delete " + urls.map(\.path).joined(separator: ","))
    }

    func renameItem(at url: URL, to newName: String) throws -> URL {
        calls.append("rename \(url.path) -> \(newName)")
        return url.deletingLastPathComponent().appendingPathComponent(newName)
    }

    func createAlias(for url: URL, in destinationFolder: URL) throws -> URL {
        destinationFolder.appendingPathComponent(url.lastPathComponent + " alias")
    }

    func setHidden(_ hidden: Bool, for url: URL) throws -> URL {
        url
    }

    func setLocked(_ locked: Bool, for url: URL) throws -> URL {
        url
    }

    func setLabel(_ labelNumber: Int, for url: URL) throws -> URL {
        url
    }
}

private struct StubResultFileOperationService: ResultFileOperationServing {
    var renamedPath: String = "/tmp/renamed.txt"

    func moveToTrash(urls: [URL]) throws -> [URL] {
        urls
    }

    func deleteImmediately(urls: [URL]) throws {}

    func renameItem(at url: URL, to newName: String) throws -> URL {
        URL(fileURLWithPath: renamedPath)
    }

    func createAlias(for url: URL, in destinationFolder: URL) throws -> URL {
        destinationFolder.appendingPathComponent(url.lastPathComponent + ".alias")
    }

    func setHidden(_ hidden: Bool, for url: URL) throws -> URL {
        url
    }

    func setLocked(_ locked: Bool, for url: URL) throws -> URL {
        url
    }

    func setLabel(_ labelNumber: Int, for url: URL) throws -> URL {
        url
    }
}
