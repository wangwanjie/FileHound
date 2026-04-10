import Foundation

struct ResultMenuState {
    let canRename: Bool
    let canMoveToTrash: Bool
    let canRemoveFromResults: Bool
}

enum ResultConfirmationRequest {
    case deleteImmediately(itemCount: Int)
}

final class ResultActionController {
    let fileService: any ResultFileOperationServing
    private let confirmationPresenter: (ResultConfirmationRequest) -> Bool

    init(
        fileService: any ResultFileOperationServing = ResultFileOperationService(),
        confirmationPresenter: @escaping (ResultConfirmationRequest) -> Bool
    ) {
        self.fileService = fileService
        self.confirmationPresenter = confirmationPresenter
    }

    func menuState(for items: [SearchResultItem]) -> ResultMenuState {
        ResultMenuState(
            canRename: items.count == 1,
            canMoveToTrash: items.isEmpty == false,
            canRemoveFromResults: items.isEmpty == false
        )
    }

    func removeFromResults(items: [SearchResultItem], viewModel: SearchResultsViewModel) {
        viewModel.removeItems(ids: Set(items.map(\.id)))
    }

    func handleRename(item: SearchResultItem, newName: String, viewModel: SearchResultsViewModel) throws {
        let updatedURL = try fileService.renameItem(at: URL(fileURLWithPath: item.path), to: newName)
        viewModel.replaceItems([item.withUpdatedPath(updatedURL.path)])
    }

    func handleDeleteImmediately(items: [SearchResultItem], viewModel: SearchResultsViewModel) throws {
        guard items.isEmpty == false else {
            return
        }

        guard confirmationPresenter(.deleteImmediately(itemCount: items.count)) else {
            return
        }

        try fileService.deleteImmediately(urls: items.map { URL(fileURLWithPath: $0.path) })
        viewModel.removeItems(ids: Set(items.map(\.id)))
    }
}
