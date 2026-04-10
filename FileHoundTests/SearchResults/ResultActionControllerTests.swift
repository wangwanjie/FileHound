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
            confirmationPresenter: { _ in true }
        )

        try controller.handleRename(item: second, newName: "renamed.txt", viewModel: viewModel)
        #expect(viewModel.items.map(\.path).contains("/tmp/renamed.txt"))

        try controller.handleDeleteImmediately(items: [first], viewModel: viewModel)
        #expect(viewModel.items.map(\.path) == ["/tmp/renamed.txt"])

        controller.removeFromResults(items: [viewModel.items[0]], viewModel: viewModel)
        #expect(viewModel.items.isEmpty)
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
}
