import Foundation
import Testing
@testable import FileHound

struct SearchResultsViewModelTests {
    @Test
    func applyingPresentationStateNotifiesProjectionOnce() {
        let viewModel = SearchResultsViewModel()
        viewModel.items = [
            SearchResultItem(path: "/z/report.lookin", matchReason: "", previewSnippet: nil),
            SearchResultItem(path: "/a/report.lookin", matchReason: "", previewSnippet: nil),
            SearchResultItem(path: "/a/other.txt", matchReason: "", previewSnippet: nil)
        ]
        var notifiedProjections: [[String]] = []
        viewModel.onItemsChange = { items in
            notifiedProjections.append(items.map(\.path))
        }

        viewModel.apply(presentationState: ResultPresentationState(
            mode: .tree,
            sortField: .path,
            sortOrder: .descending,
            filterText: "lookin",
            showInvisibleItems: true,
            showPackageContents: true,
            showTrashedItems: true,
            previewSize: 96
        ))

        // 多个属性同时变化只刷新一次，且是全部条件生效后的结果
        #expect(notifiedProjections == [["/z/report.lookin", "/a/report.lookin"]])
        #expect(viewModel.mode == .tree)
    }

    @Test
    func projectedItemsAreCachedUntilInputsChange() {
        let viewModel = SearchResultsViewModel()
        viewModel.items = [
            SearchResultItem(path: "/b.txt", matchReason: "", previewSnippet: nil),
            SearchResultItem(path: "/a.txt", matchReason: "", previewSnippet: nil)
        ]
        #expect(viewModel.projectedItems.map(\.path) == ["/a.txt", "/b.txt"])

        viewModel.sortOrder = .descending
        #expect(viewModel.projectedItems.map(\.path) == ["/b.txt", "/a.txt"])

        viewModel.filterText = "a"
        #expect(viewModel.projectedItems.map(\.path) == ["/a.txt"])

        viewModel.items.append(SearchResultItem(path: "/aa.txt", matchReason: "", previewSnippet: nil))
        #expect(viewModel.projectedItems.map(\.path) == ["/aa.txt", "/a.txt"])
    }

    @Test
    func projectedItemsHideInvisibleItemsByDefault() {
        let visible = SearchResultItem(path: "/tmp/visible.lookin", matchReason: "名称命中", previewSnippet: nil)
        let hidden = SearchResultItem(path: "/tmp/.hidden.lookin", matchReason: "名称命中", previewSnippet: nil, isInvisible: true)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [visible, hidden]

        #expect(viewModel.projectedItems == [visible])

        viewModel.showInvisibleItems = true
        #expect(viewModel.projectedItems.count == 2)
    }

    @Test
    func togglesPackageFilterWithoutDroppingVisibleFiles() {
        let package = SearchResultItem(path: "/tmp/Demo.app", matchReason: "名称命中", previewSnippet: nil, isPackage: true)
        let packageContent = SearchResultItem(path: "/tmp/Demo.app/Contents/Info.plist", matchReason: "名称命中", previewSnippet: nil)
        let file = SearchResultItem(path: "/tmp/Demo.lookin", matchReason: "名称命中", previewSnippet: nil)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [package, packageContent, file]

        #expect(Set(viewModel.projectedItems.map(\.path)) == ["/tmp/Demo.app", "/tmp/Demo.lookin"])
        viewModel.showPackageContents = true
        #expect(viewModel.projectedItems.count == 3)
    }

    @Test
    func packageItemsStayVisibleWhenPackageContentsAreHidden() {
        let package = SearchResultItem(path: "/Users/demo/Downloads/App.dmgcanvas", matchReason: "名称命中", previewSnippet: nil, isPackage: true)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [package]

        #expect(viewModel.showPackageContents == false)
        #expect(viewModel.projectedItems == [package])
    }

    @Test
    func sortByPathUsesFullPathInsteadOfDisplayName() {
        let a = SearchResultItem(path: "/z/report.lookin", matchReason: "名称命中", previewSnippet: nil)
        let b = SearchResultItem(path: "/a/report.lookin", matchReason: "名称命中", previewSnippet: nil)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [a, b]
        viewModel.sortField = .path

        #expect(viewModel.projectedItems.map(\.path) == ["/a/report.lookin", "/z/report.lookin"])
    }

    @Test
    func descendingSortReversesProjectedItems() {
        let a = SearchResultItem(path: "/z/report.lookin", matchReason: "名称命中", previewSnippet: nil)
        let b = SearchResultItem(path: "/a/report.lookin", matchReason: "名称命中", previewSnippet: nil)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [a, b]
        viewModel.sortField = .path
        viewModel.sortOrder = .descending

        #expect(viewModel.projectedItems.map(\.path) == ["/z/report.lookin", "/a/report.lookin"])
    }

    @Test
    func removesUpdatedAndSelectedItemsWithoutRebuildingWindow() {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "名称命中", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "名称命中", previewSnippet: nil)

        let viewModel = SearchResultsViewModel()
        viewModel.items = [first, second]
        viewModel.selectedIDs = [first.id, second.id]

        viewModel.removeItems(ids: [first.id])
        #expect(viewModel.items.map(\.path) == ["/tmp/b.txt"])
        #expect(viewModel.selectedIDs == [second.id])

        let renamed = second.withUpdatedPath("/tmp/renamed.txt")
        viewModel.replaceItems([renamed])
        #expect(viewModel.items.map(\.path) == ["/tmp/renamed.txt"])
    }

    @Test
    func trashedItemsReappearAfterBeingPutBack() {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "名称命中", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "名称命中", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [first, second]
        viewModel.markItemsTrashed([
            TrashedResultEntry(item: first, trashedPath: "/Users/me/.Trash/a.txt"),
            TrashedResultEntry(item: second, trashedPath: "/Users/me/.Trash/b.txt")
        ])
        #expect(viewModel.items.isEmpty)

        // a 仍在废纸篓，b 已被放回原处
        var existing: Set<String> = ["/Users/me/.Trash/a.txt", "/tmp/b.txt"]
        let restored = viewModel.restoreItemsPutBackFromTrash(fileExists: { existing.contains($0) })
        #expect(restored.map(\.id) == [second.id])
        #expect(viewModel.items.map(\.path) == ["/tmp/b.txt"])
        #expect(viewModel.trashedEntries.map(\.item.id) == [first.id])

        // 废纸篓被清空后不再跟踪
        existing = ["/tmp/b.txt"]
        #expect(viewModel.restoreItemsPutBackFromTrash(fileExists: { existing.contains($0) }).isEmpty)
        #expect(viewModel.trashedEntries.isEmpty)
    }

    @Test
    func selectionFollowsPathsWhenItemsAreReplaced() {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [first, second]
        viewModel.selectedIDs = [second.id]
        viewModel.selectedItem = second

        // 流式进度可能带来同路径的新对象（ID 不同），选中按路径迁移
        let refreshedSecond = SearchResultItem(path: "/tmp/b.txt", matchReason: "", previewSnippet: nil)
        viewModel.items = [first, refreshedSecond]

        #expect(viewModel.selectedItems.map(\.path) == ["/tmp/b.txt"])
        #expect(viewModel.selectedItem?.id == refreshedSecond.id)
    }

    @Test
    func streamingProgressReappliesRenamesIncludingDescendants() {
        let folder = SearchResultItem(path: "/tmp/demo", matchReason: "", previewSnippet: nil)
        let child = SearchResultItem(path: "/tmp/demo/a.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.beginNewSearch(with: [folder, child])

        viewModel.applyRename(from: "/tmp/demo", to: folder.withUpdatedPath("/tmp/renamed"))
        #expect(viewModel.items.map(\.path) == ["/tmp/renamed", "/tmp/renamed/a.txt"])

        // 后续进度仍带着旧路径，并出现新的后代结果
        let lateChild = SearchResultItem(path: "/tmp/demo/b.txt", matchReason: "", previewSnippet: nil)
        viewModel.mergeSearchProgress([folder, child, lateChild])
        #expect(viewModel.items.map(\.path) == ["/tmp/renamed", "/tmp/renamed/a.txt", "/tmp/renamed/b.txt"])

        // 连续改名与改回原名
        viewModel.applyRename(from: "/tmp/renamed", to: folder.withUpdatedPath("/tmp/final"))
        viewModel.mergeSearchProgress([folder, child])
        #expect(viewModel.items.map(\.path) == ["/tmp/final", "/tmp/final/a.txt"])
        viewModel.applyRename(from: "/tmp/final", to: folder)
        viewModel.mergeSearchProgress([folder, child])
        #expect(viewModel.items.map(\.path) == ["/tmp/demo", "/tmp/demo/a.txt"])
    }

    @Test
    func streamingProgressKeepsTrashedSubtreesAndAttributeChanges() {
        let folder = SearchResultItem(path: "/tmp/demo", matchReason: "", previewSnippet: nil)
        let child = SearchResultItem(path: "/tmp/demo/a.txt", matchReason: "", previewSnippet: nil)
        let other = SearchResultItem(path: "/tmp/other.txt", matchReason: "", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.beginNewSearch(with: [folder, child, other])

        viewModel.markItemsTrashed([TrashedResultEntry(item: folder, trashedPath: "/Users/me/.Trash/demo")])
        let hiddenOther = SearchResultItem(id: other.id, path: other.path, matchReason: "", previewSnippet: nil, isInvisible: true)
        viewModel.replaceItems([hiddenOther])
        #expect(viewModel.items == [hiddenOther])

        let lateChild = SearchResultItem(path: "/tmp/demo/late.txt", matchReason: "", previewSnippet: nil)
        viewModel.mergeSearchProgress([folder, child, lateChild, other])
        #expect(viewModel.items.map(\.path) == ["/tmp/other.txt"])
        #expect(viewModel.items.first?.isInvisible == true)

        viewModel.beginNewSearch(with: [folder, other])
        #expect(viewModel.items.map(\.path) == ["/tmp/demo", "/tmp/other.txt"])
        #expect(viewModel.items.last?.isInvisible == false)
    }

    @Test
    func csvExportEscapesSpecialCharactersAndKeepsChinese() {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let items = [
            SearchResultItem(
                path: "/Users/me/报告,\"终版\".txt",
                matchReason: "",
                previewSnippet: nil,
                kind: "纯文本",
                modifiedDate: modified,
                sizeBytes: 1024
            ),
            SearchResultItem(path: "/tmp/line\nbreak", matchReason: "", previewSnippet: nil, kind: "Folder")
        ]

        let csv = ResultExportFormatter.csvString(for: items, timeZone: TimeZone(identifier: "UTC")!)
        let lines = csv.components(separatedBy: "\r\n")

        #expect(lines[0] == [
            "results.export.column.name", "results.export.column.path", "results.export.column.size_bytes",
            "results.export.column.modified", "results.export.column.kind"
        ].map(L10n.string).joined(separator: ","))
        #expect(lines[1] == #""报告,""终版"".txt","/Users/me/报告,""终版"".txt",1024,2023-11-14T22:13:20Z,纯文本"#)
        // 含换行的字段整体加引号，换行保留在引号内
        #expect(lines[2] == "\"line\nbreak\",\"/tmp/line\nbreak\",,,Folder")
        #expect(lines.count == 4 && lines[3].isEmpty)
    }

    @Test
    func csvDataStartsWithUTF8BOMAndPlainTextListsPaths() {
        let items = [
            SearchResultItem(path: "/tmp/中文.txt", matchReason: "", previewSnippet: nil),
            SearchResultItem(path: "/tmp/b c.txt", matchReason: "", previewSnippet: nil)
        ]

        let csvData = ResultExportFormatter.data(for: items, format: .csv)
        #expect(Array(csvData.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(data: csvData.dropFirst(3), encoding: .utf8)?.contains("/tmp/中文.txt") == true)

        let textData = ResultExportFormatter.data(for: items, format: .plainText)
        #expect(String(data: textData, encoding: .utf8) == "/tmp/中文.txt\n/tmp/b c.txt\n")
        #expect(Array(textData.prefix(3)) != [0xEF, 0xBB, 0xBF])
    }

    @Test
    func csvFieldsWithoutSpecialCharactersAreNotQuoted() {
        #expect(ResultExportFormatter.csvEscaped("plain 名称") == "plain 名称")
        #expect(ResultExportFormatter.csvEscaped("a,b") == "\"a,b\"")
        #expect(ResultExportFormatter.csvEscaped("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(ResultExportFormatter.csvEscaped("a\r\nb") == "\"a\r\nb\"")
        #expect(ResultExportFormatter.suggestedFileName(title: "Name: a/b", fallback: "Results", format: .plainText) == "Name- a-b.txt")
        #expect(ResultExportFormatter.suggestedFileName(title: "  ", fallback: "Results", format: .csv) == "Results.csv")
    }

    @Test
    func presentationStateRoundTripsThroughViewModel() {
        let state = ResultPresentationState(
            mode: .table,
            sortField: .path,
            sortOrder: .descending,
            filterText: "report",
            showInvisibleItems: true,
            showPackageContents: true,
            showTrashedItems: true,
            previewSize: 104
        )
        let viewModel = SearchResultsViewModel()

        viewModel.apply(presentationState: state)

        #expect(viewModel.presentationState == state)
    }
}
