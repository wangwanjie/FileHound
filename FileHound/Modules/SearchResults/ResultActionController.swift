import Foundation

struct ResultMenuState {
    let canRename: Bool
    let canMoveToTrash: Bool
    let canRemoveFromResults: Bool
    /// 隐藏 / 解锁 / 设置标签等修改文件属性的操作
    let canModifyAttributes: Bool
}

enum ResultConfirmationRequest: Equatable {
    case deleteImmediately(items: [SearchResultItem])

    /// 确认框正文：单个项目写出名称与路径，多个项目写出数量
    var informativeText: String {
        switch self {
        case .deleteImmediately(let items):
            if items.count == 1, let item = items.first {
                return L10n.format("results.delete.single_named", item.displayName, item.path)
            }
            return L10n.format("results.delete.multiple", Int64(items.count))
        }
    }
}

final class ResultActionController {
    let fileService: any ResultFileOperationServing
    private let confirmationPresenter: (ResultConfirmationRequest) -> Bool
    private let itemRefresher: (SearchResultItem, String) -> SearchResultItem?

    init(
        fileService: any ResultFileOperationServing = ResultFileOperationService(),
        itemRefresher: @escaping (SearchResultItem, String) -> SearchResultItem? = ResultItemRefresher.refreshedItem(from:atPath:),
        confirmationPresenter: @escaping (ResultConfirmationRequest) -> Bool
    ) {
        self.fileService = fileService
        self.itemRefresher = itemRefresher
        self.confirmationPresenter = confirmationPresenter
    }

    /// isMatchedResult 区分真实结果与树视图补出的上级文件夹节点：后者只允许打开、显示、拷贝等非破坏性操作
    func menuState(
        for items: [SearchResultItem],
        isMatchedResult: (SearchResultItem) -> Bool = { _ in true }
    ) -> ResultMenuState {
        let allMatched = items.isEmpty == false && items.allSatisfy(isMatchedResult)
        return ResultMenuState(
            canRename: items.count == 1 && allMatched,
            canMoveToTrash: allMatched,
            canRemoveFromResults: allMatched,
            canModifyAttributes: allMatched
        )
    }

    /// 只保留视图模型中真实存在的结果，防止对合成节点执行破坏性操作
    private func matchedItems(_ items: [SearchResultItem], in viewModel: SearchResultsViewModel) -> [SearchResultItem] {
        items.filter { viewModel.containsItem(id: $0.id) }
    }

    func removeFromResults(items: [SearchResultItem], viewModel: SearchResultsViewModel) {
        viewModel.removeItems(ids: Set(matchedItems(items, in: viewModel).map(\.id)))
    }

    func handleMoveToTrash(items: [SearchResultItem], viewModel: SearchResultsViewModel) throws {
        let items = matchedItems(items, in: viewModel)
        guard items.isEmpty == false else {
            return
        }

        var entries: [TrashedResultEntry] = []
        var firstError: Error?

        for item in items {
            do {
                let trashedURLs = try fileService.moveToTrash(urls: [URL(fileURLWithPath: item.path)])
                entries.append(TrashedResultEntry(item: item, trashedPath: trashedURLs.first?.path ?? item.path))
            } catch {
                firstError = firstError ?? error
            }
        }

        viewModel.markItemsTrashed(entries)
        if let firstError {
            throw firstError
        }
    }

    /// 校验新名称后改名；名称未变化时不做任何操作。改名后重新读取文件属性（如以 "." 开头后变为隐藏），
    /// 并把以旧路径为前缀的后代结果一起换成新路径
    func handleRename(item: SearchResultItem, newName: String, viewModel: SearchResultsViewModel) throws {
        guard viewModel.containsItem(id: item.id) else {
            return
        }
        guard let validatedName = try ResultRenameValidator.validatedName(newName, originalName: item.displayName) else {
            return
        }

        let updatedURL = try fileService.renameItem(at: URL(fileURLWithPath: item.path), to: validatedName)
        let renamedItem = itemRefresher(item, updatedURL.path) ?? item.withUpdatedPath(updatedURL.path)
        viewModel.applyRename(from: item.path, to: renamedItem)
    }

    func handleDeleteImmediately(items: [SearchResultItem], viewModel: SearchResultsViewModel) throws {
        let items = matchedItems(items, in: viewModel)
        guard items.isEmpty == false else {
            return
        }

        guard confirmationPresenter(.deleteImmediately(items: items)) else {
            return
        }

        var deletedPaths = Set<String>()
        var firstError: Error?

        for item in items {
            do {
                try fileService.deleteImmediately(urls: [URL(fileURLWithPath: item.path)])
                deletedPaths.insert(item.path)
            } catch {
                firstError = firstError ?? error
            }
        }

        // 删除文件夹后其中的后代结果也已不存在，一并移除
        viewModel.removeItemsAndDescendants(paths: deletedPaths)

        if let firstError {
            throw firstError
        }
    }
}

/// 文件操作（改名、隐藏、解锁、标签、放回原处）后重新读取文件属性，生成更新后的结果项
enum ResultItemRefresher {
    static func refreshedItem(from item: SearchResultItem, atPath path: String) -> SearchResultItem? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let resourceValues = try? url.resourceValues(forKeys: [
            .isHiddenKey,
            .tagNamesKey,
            .isApplicationKey,
            .creationDateKey,
            .contentAccessDateKey,
            .addedToDirectoryDateKey
        ])
        let createdDate = (attributes[.creationDate] as? Date) ?? resourceValues?.creationDate
        return SearchResultItem(
            id: item.id,
            path: path,
            matchReason: item.matchReason,
            previewSnippet: item.previewSnippet,
            highlightKind: item.highlightKind,
            highlightQuery: item.highlightQuery,
            kind: item.kind,
            modifiedText: displayDate(attributes[.modificationDate] as? Date),
            createdText: displayDate(createdDate),
            lastOpenedText: displayDate(resourceValues?.contentAccessDate),
            addedText: displayDate(resourceValues?.addedToDirectoryDate),
            sizeText: displaySize(attributes: attributes),
            tagsText: resourceValues?.tagNames?.joined(separator: ", ") ?? item.tagsText,
            enclosingFolder: url.deletingLastPathComponent().path,
            isInvisible: resourceValues?.isHidden == true,
            isPackage: resourceValues?.isApplication == true || item.isPackage,
            isTrashed: item.isTrashed,
            modifiedDate: attributes[.modificationDate] as? Date,
            createdDate: createdDate,
            lastOpenedDate: resourceValues?.contentAccessDate,
            addedDate: resourceValues?.addedToDirectoryDate,
            sizeBytes: (attributes[.size] as? NSNumber)?.int64Value,
            tags: resourceValues?.tagNames ?? item.tags
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func displayDate(_ date: Date?) -> String {
        guard let date else {
            return ""
        }

        return dateFormatter.string(from: date)
    }

    private static func displaySize(attributes: [FileAttributeKey: Any]) -> String {
        guard let size = attributes[.size] as? NSNumber else {
            return ""
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size.int64Value)
    }
}
