# FileHound Results Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Finder-like multi-selection result actions, Finder/QuickLook-style result icons, and adaptive main-window rule-area sizing without using a separate worktree.

**Architecture:** Introduce a shared result action layer plus a shared icon provider so grid/table/tree views stop owning file-operation logic. Add a small main-window layout coordinator so rule-row growth first resizes/repositions the window and then falls back to a scrollable rule area while keeping the bottom action bar pinned.

**Tech Stack:** Swift, AppKit, SnapKit, NSWorkspace, NSMenu, QuickLookThumbnailing, FileManager, URL resource values, XCTest/Testing

---

## File Map

- Modify: `FileHound/Modules/SearchResults/SearchResultsViewModel.swift`
  Responsibility: hold selection set, removal/update operations, and refresh hooks shared by all result views.
- Modify: `FileHound/Modules/SearchResults/SearchResultsViewController.swift`
  Responsibility: connect shared selection/actions/icon refresh to grid/table/tree views.
- Modify: `FileHound/Modules/SearchResults/ResultsCollectionViewController.swift`
  Responsibility: support multi-selection, context menus, double-click/open, Finder-style icon/thumbnail cells.
- Modify: `FileHound/Modules/SearchResults/ResultsTableViewController.swift`
  Responsibility: support multi-selection, context menus, Finder-style icon cells, inline rename trigger hookup.
- Modify: `FileHound/Modules/SearchResults/ResultsOutlineViewController.swift`
  Responsibility: support multi-selection, context menus, Finder-style icon cells for outline rows.
- Create: `FileHound/Modules/SearchResults/ResultActionController.swift`
  Responsibility: build context menus, dispatch file operations, coordinate batch execution and user confirmations.
- Create: `FileHound/Modules/SearchResults/ResultIconProvider.swift`
  Responsibility: provide cached Finder/QuickLook-style icons and thumbnails asynchronously.
- Create: `FileHound/Modules/SearchResults/ResultContextMenuFactory.swift`
  Responsibility: build `Open With`, `Set Label`, `Services`, and destructive-action submenus.
- Create: `FileHound/Modules/SearchResults/ResultFileOperationService.swift`
  Responsibility: wrap trash/delete/rename/alias/hidden/locked/tag/path operations and return updated item state.
- Modify: `FileHound/SearchEngine/Streaming/SearchResultItem.swift`
  Responsibility: carry the metadata needed for action enablement and refresh.
- Modify: `FileHound/Modules/SearchWindow/SearchFormViewController.swift`
  Responsibility: host scrollable rule area, recalculate desired height, reposition within visible frame, update title.
- Modify: `FileHound/Modules/SearchWindow/SearchWindowController.swift`
  Responsibility: own adaptive window sizing/reposition policy and app title.
- Modify: `FileHound/Modules/SearchRules/SearchRuleListView.swift`
  Responsibility: expose a scroll-capable rule container and content height measurement.
- Modify: `FileHound/Modules/SearchRules/SearchRulesViewController.swift`
  Responsibility: notify window when rule count changes.
- Test: `FileHoundTests/SearchResults/SearchResultsViewModelTests.swift`
  Responsibility: projection refresh and removal/update behavior.
- Create: `FileHoundTests/SearchResults/ResultActionControllerTests.swift`
  Responsibility: batch action enablement, removal/update rules, non-destructive menu behavior.
- Create: `FileHoundTests/SearchResults/ResultFileOperationServiceTests.swift`
  Responsibility: file mutation behavior against temp fixtures.
- Create: `FileHoundTests/SearchWindow/SearchWindowLayoutCoordinatorTests.swift`
  Responsibility: window growth/reposition/scroll fallback policy.

### Task 1: Lock Main Window Adaptive Layout Contract

**Files:**
- Modify: `FileHoundTests/SearchWindow/SearchWindowControllerTests.swift`
- Create: `FileHoundTests/SearchWindow/SearchWindowLayoutCoordinatorTests.swift`
- Modify: `FileHound/Modules/SearchRules/SearchRuleListView.swift`
- Modify: `FileHound/Modules/SearchRules/SearchRulesViewController.swift`
- Modify: `FileHound/Modules/SearchWindow/SearchFormViewController.swift`
- Modify: `FileHound/Modules/SearchWindow/SearchWindowController.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import AppKit
import Testing
@testable import FileHound

struct SearchWindowLayoutCoordinatorTests {
    @Test
    func expandsWindowUntilVisibleFrameLimitThenEnablesRuleScrolling() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        let coordinator = SearchWindowLayoutCoordinator(visibleFrameProvider: { visibleFrame })

        let compact = coordinator.layout(
            currentFrame: NSRect(x: 200, y: 300, width: 760, height: 220),
            ruleContentHeight: 180,
            minimumWindowHeight: 220,
            maximumRuleAreaHeight: 320,
            chromeHeight: 108
        )
        #expect(compact.shouldScrollRules == false)

        let oversized = coordinator.layout(
            currentFrame: NSRect(x: 200, y: 100, width: 760, height: 220),
            ruleContentHeight: 520,
            minimumWindowHeight: 220,
            maximumRuleAreaHeight: 320,
            chromeHeight: 108
        )
        #expect(oversized.frame.maxY == visibleFrame.maxY)
        #expect(oversized.shouldScrollRules == true)
    }
}
```

```swift
import AppKit
import Testing
@testable import FileHound

struct SearchWindowControllerTests {
    @MainActor
    @Test
    func usesProjectTitleAndNarrowerDefaultWidth() {
        let controller = SearchWindowController()
        let window = try! #require(controller.window)

        #expect(window.title == "FileHound")
        #expect(window.contentLayoutRect.width <= 820)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchWindowLayoutCoordinatorTests -only-testing:FileHoundTests/SearchWindowControllerTests`

Expected: FAIL because `SearchWindowLayoutCoordinator` does not exist and the window title/default width still reflect old behavior.

- [ ] **Step 3: Write minimal implementation**

```swift
struct SearchWindowLayout {
    let frame: NSRect
    let ruleAreaHeight: CGFloat
    let shouldScrollRules: Bool
}

struct SearchWindowLayoutCoordinator {
    var visibleFrameProvider: () -> NSRect

    func layout(
        currentFrame: NSRect,
        ruleContentHeight: CGFloat,
        minimumWindowHeight: CGFloat,
        maximumRuleAreaHeight: CGFloat,
        chromeHeight: CGFloat
    ) -> SearchWindowLayout {
        let visibleFrame = visibleFrameProvider()
        let cappedRuleAreaHeight = min(ruleContentHeight, maximumRuleAreaHeight)
        let desiredHeight = max(minimumWindowHeight, chromeHeight + cappedRuleAreaHeight)
        let maxAllowedHeight = visibleFrame.height
        let finalHeight = min(desiredHeight, maxAllowedHeight)
        let finalOriginY = max(visibleFrame.minY, min(currentFrame.origin.y, visibleFrame.maxY - finalHeight))
        let needsScrolling = chromeHeight + ruleContentHeight > maxAllowedHeight

        return SearchWindowLayout(
            frame: NSRect(x: currentFrame.origin.x, y: finalOriginY, width: currentFrame.width, height: finalHeight),
            ruleAreaHeight: max(0, finalHeight - chromeHeight),
            shouldScrollRules: needsScrolling
        )
    }
}
```

```swift
final class SearchWindowController: NSWindowController {
    private let layoutCoordinator = SearchWindowLayoutCoordinator {
        NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
    }

    convenience init() {
        let formController = SearchFormViewController()
        let window = NSWindow(contentViewController: formController)
        window.title = "FileHound"
        window.setContentSize(NSSize(width: 800, height: 236))
        self.init(window: window)
        formController.windowLayoutDelegate = self
    }
}
```

```swift
protocol SearchWindowLayoutDelegate: AnyObject {
    func searchRulesDidChange(contentHeight: CGFloat)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchWindowLayoutCoordinatorTests -only-testing:FileHoundTests/SearchWindowControllerTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add FileHound/Modules/SearchWindow/SearchWindowController.swift \
  FileHound/Modules/SearchWindow/SearchFormViewController.swift \
  FileHound/Modules/SearchRules/SearchRuleListView.swift \
  FileHound/Modules/SearchRules/SearchRulesViewController.swift \
  FileHoundTests/SearchWindow/SearchWindowControllerTests.swift \
  FileHoundTests/SearchWindow/SearchWindowLayoutCoordinatorTests.swift
git commit -m "feat: add adaptive search window layout"
```

### Task 2: Add Shared Result Selection And Refresh Primitives

**Files:**
- Modify: `FileHound/SearchEngine/Streaming/SearchResultItem.swift`
- Modify: `FileHound/Modules/SearchResults/SearchResultsViewModel.swift`
- Modify: `FileHoundTests/SearchResults/SearchResultsViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import FileHound

struct SearchResultsViewModelTests {
    @Test
    func removesUpdatedAndSelectedItemsWithoutRebuildingWindow() {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "name", previewSnippet: "a")
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "name", previewSnippet: "b")
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchResultsViewModelTests`

Expected: FAIL because `selectedIDs`, `removeItems`, `replaceItems`, and `withUpdatedPath` do not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
struct SearchResultItem: Equatable, Identifiable, Sendable {
    // existing fields...

    func withUpdatedPath(_ newPath: String) -> SearchResultItem {
        SearchResultItem(
            id: id,
            path: newPath,
            matchReason: matchReason,
            previewSnippet: previewSnippet,
            kind: kind,
            modifiedText: modifiedText,
            createdText: createdText,
            lastOpenedText: lastOpenedText,
            addedText: addedText,
            sizeText: sizeText,
            tagsText: tagsText,
            enclosingFolder: URL(fileURLWithPath: newPath).deletingLastPathComponent().path,
            isInvisible: isInvisible,
            isPackage: isPackage,
            isTrashed: isTrashed
        )
    }
}
```

```swift
final class SearchResultsViewModel {
    var selectedIDs: Set<SearchResultItem.ID> = [] {
        didSet { onSelectionSetChange?(selectedIDs) }
    }

    var onSelectionSetChange: ((Set<SearchResultItem.ID>) -> Void)?

    func removeItems(ids: Set<SearchResultItem.ID>) {
        items.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        notifyProjectionChanged()
    }

    func replaceItems(_ updatedItems: [SearchResultItem]) {
        let map = Dictionary(uniqueKeysWithValues: updatedItems.map { ($0.id, $0) })
        items = items.map { map[$0.id] ?? $0 }
        notifyProjectionChanged()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchResultsViewModelTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add FileHound/SearchEngine/Streaming/SearchResultItem.swift \
  FileHound/Modules/SearchResults/SearchResultsViewModel.swift \
  FileHoundTests/SearchResults/SearchResultsViewModelTests.swift
git commit -m "feat: add shared result refresh primitives"
```

### Task 3: Add Result File Operation Service

**Files:**
- Create: `FileHound/Modules/SearchResults/ResultFileOperationService.swift`
- Create: `FileHoundTests/SearchResults/ResultFileOperationServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import FileHound

struct ResultFileOperationServiceTests {
    @Test
    func renamesAliasesAndTogglesVisibilityOnFixtureFiles() throws {
        let fixture = try TemporaryFixtureTree.make { builder in
            try builder.file("report.txt", contents: "hello")
        }

        let service = ResultFileOperationService()
        let sourceURL = URL(fileURLWithPath: fixture.path).appendingPathComponent("report.txt")

        let renamedURL = try service.renameItem(at: sourceURL, to: "renamed.txt")
        #expect(renamedURL.lastPathComponent == "renamed.txt")

        let aliasURL = try service.createAlias(for: renamedURL, in: URL(fileURLWithPath: fixture.path))
        #expect(FileManager.default.fileExists(atPath: aliasURL.path))

        let hiddenURL = try service.setHidden(true, for: renamedURL)
        let values = try hiddenURL.resourceValues(forKeys: [.isHiddenKey])
        #expect(values.isHidden == true)

        let unlockedURL = try service.setLocked(false, for: hiddenURL)
        let unlockedValues = try unlockedURL.resourceValues(forKeys: [.isUserImmutableKey])
        #expect(unlockedValues.isUserImmutable != true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/ResultFileOperationServiceTests`

Expected: FAIL because `ResultFileOperationService` does not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
import AppKit
import Foundation

struct ResultFileOperationService {
    func moveToTrash(urls: [URL]) throws -> [URL] {
        try urls.map { url in
            var trashed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            return trashed as URL? ?? url
        }
    }

    func deleteImmediately(urls: [URL]) throws {
        try urls.forEach { try FileManager.default.removeItem(at: $0) }
    }

    func renameItem(at url: URL, to newName: String) throws -> URL {
        let target = url.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    func createAlias(for url: URL, in destinationFolder: URL) throws -> URL {
        let aliasData = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        let aliasURL = destinationFolder.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " alias")
            .appendingPathExtension(url.pathExtension.isEmpty ? "alias" : url.pathExtension + ".alias")
        try URL.writeBookmarkData(aliasData, to: aliasURL)
        return aliasURL
    }

    func setHidden(_ hidden: Bool, for url: URL) throws -> URL {
        var values = URLResourceValues()
        values.isHidden = hidden
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        return mutableURL
    }

    func setLocked(_ locked: Bool, for url: URL) throws -> URL {
        var values = URLResourceValues()
        values.isUserImmutable = locked
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        return mutableURL
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/ResultFileOperationServiceTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add FileHound/Modules/SearchResults/ResultFileOperationService.swift \
  FileHoundTests/SearchResults/ResultFileOperationServiceTests.swift
git commit -m "feat: add result file mutation service"
```

### Task 4: Add Shared Result Action Controller And Menu Factory

**Files:**
- Create: `FileHound/Modules/SearchResults/ResultActionController.swift`
- Create: `FileHound/Modules/SearchResults/ResultContextMenuFactory.swift`
- Create: `FileHoundTests/SearchResults/ResultActionControllerTests.swift`
- Modify: `FileHound/Modules/SearchResults/SearchResultsViewController.swift`
- Modify: `FileHound/Modules/SearchResults/SearchResultsViewModel.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import FileHound

struct ResultActionControllerTests {
    @Test
    func renameIsDisabledForMultiSelectionButTrashAndRemoveRemainEnabled() {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "name", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "name", previewSnippet: nil)
        let controller = ResultActionController(
            fileService: .stub,
            workspace: .stub,
            confirmationPresenter: { _ in true }
        )

        let state = controller.menuState(for: [first, second])
        #expect(state.canRename == false)
        #expect(state.canMoveToTrash == true)
        #expect(state.canRemoveFromResults == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/ResultActionControllerTests`

Expected: FAIL because `ResultActionController` does not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
struct ResultMenuState {
    let canRename: Bool
    let canMoveToTrash: Bool
    let canRemoveFromResults: Bool
}

final class ResultActionController {
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
}
```

```swift
final class SearchResultsViewController: NSViewController {
    private lazy var actionController = ResultActionController(...)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/ResultActionControllerTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add FileHound/Modules/SearchResults/ResultActionController.swift \
  FileHound/Modules/SearchResults/ResultContextMenuFactory.swift \
  FileHound/Modules/SearchResults/SearchResultsViewController.swift \
  FileHound/Modules/SearchResults/SearchResultsViewModel.swift \
  FileHoundTests/SearchResults/ResultActionControllerTests.swift
git commit -m "feat: add shared result action controller"
```

### Task 5: Wire Grid/Table/Tree Multi-Selection And Context Menus

**Files:**
- Modify: `FileHound/Modules/SearchResults/ResultsCollectionViewController.swift`
- Modify: `FileHound/Modules/SearchResults/ResultsTableViewController.swift`
- Modify: `FileHound/Modules/SearchResults/ResultsOutlineViewController.swift`
- Modify: `FileHound/Modules/SearchResults/SearchResultsViewController.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import AppKit
import Testing
@testable import FileHound

struct SearchResultsViewControllerTests {
    @MainActor
    @Test
    func propagatesMultiSelectionIntoSharedViewModel() {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "name", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "name", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [first, second]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        controller.debugSelectRows([0, 1], mode: .table)
        #expect(viewModel.selectedIDs == [first.id, second.id])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchResultsViewControllerTests`

Expected: FAIL because views only support single selection and no debug hook exists.

- [ ] **Step 3: Write minimal implementation**

```swift
final class ResultsTableViewController: NSViewController {
    var onSelectionSetChange: ((Set<SearchResultItem>) -> Void)?

    @objc
    private func selectionDidChange() {
        let selected = Set(tableView.selectedRowIndexes.compactMap { index in
            guard items.indices.contains(index) else { return nil }
            return items[index]
        })
        onSelectionSetChange?(selected)
    }
}
```

```swift
final class SearchResultsViewController: NSViewController {
    private func bindSelection() {
        tableController.onSelectionSetChange = { [weak self] items in
            self?.viewModel.selectedIDs = Set(items.map(\.id))
        }
        // mirror for grid and outline
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchResultsViewControllerTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add FileHound/Modules/SearchResults/SearchResultsViewController.swift \
  FileHound/Modules/SearchResults/ResultsCollectionViewController.swift \
  FileHound/Modules/SearchResults/ResultsTableViewController.swift \
  FileHound/Modules/SearchResults/ResultsOutlineViewController.swift \
  FileHoundTests/SearchResults/SearchResultsViewControllerTests.swift
git commit -m "feat: wire multi-selection across result views"
```

### Task 6: Add Finder/QuickLook Icon Provider

**Files:**
- Create: `FileHound/Modules/SearchResults/ResultIconProvider.swift`
- Modify: `FileHound/Modules/SearchResults/ResultsCollectionViewController.swift`
- Modify: `FileHound/Modules/SearchResults/ResultsTableViewController.swift`
- Modify: `FileHound/Modules/SearchResults/ResultsOutlineViewController.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import AppKit
import Testing
@testable import FileHound

struct ResultIconProviderTests {
    @MainActor
    @Test
    func fallsBackToWorkspaceIconWhenThumbnailUnavailable() async {
        let provider = ResultIconProvider(
            thumbnailLoader: { _ in nil },
            workspaceIconLoader: { _ in NSImage(size: NSSize(width: 32, height: 32)) }
        )

        let icon = await provider.icon(for: URL(fileURLWithPath: "/tmp/report.txt"), size: NSSize(width: 32, height: 32))
        #expect(icon != nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/ResultIconProviderTests`

Expected: FAIL because `ResultIconProvider` does not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
import AppKit
import QuickLookThumbnailing

actor ResultIconProvider {
    private var cache: [String: NSImage] = [:]
    private let thumbnailLoader: (URL) async -> NSImage?
    private let workspaceIconLoader: (URL) -> NSImage

    init(
        thumbnailLoader: @escaping (URL) async -> NSImage? = { url in
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 96, height: 96), scale: 2, representationTypes: .thumbnail)
            return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        },
        workspaceIconLoader: @escaping (URL) -> NSImage = { url in
            NSWorkspace.shared.icon(forFile: url.path)
        }
    ) {
        self.thumbnailLoader = thumbnailLoader
        self.workspaceIconLoader = workspaceIconLoader
    }

    func icon(for url: URL, size: NSSize) async -> NSImage? {
        if let cached = cache[url.path] { return cached }
        let icon = await thumbnailLoader(url) ?? workspaceIconLoader(url)
        icon.size = size
        cache[url.path] = icon
        return icon
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/ResultIconProviderTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add FileHound/Modules/SearchResults/ResultIconProvider.swift \
  FileHound/Modules/SearchResults/ResultsCollectionViewController.swift \
  FileHound/Modules/SearchResults/ResultsTableViewController.swift \
  FileHound/Modules/SearchResults/ResultsOutlineViewController.swift \
  FileHoundTests/SearchResults/ResultIconProviderTests.swift
git commit -m "feat: add finder-style result icons"
```

### Task 7: Implement Full Context Menu Actions And Live Refresh

**Files:**
- Modify: `FileHound/Modules/SearchResults/ResultActionController.swift`
- Modify: `FileHound/Modules/SearchResults/ResultContextMenuFactory.swift`
- Modify: `FileHound/Modules/SearchResults/ResultFileOperationService.swift`
- Modify: `FileHound/Modules/SearchResults/SearchResultsViewController.swift`
- Modify: `FileHound/Modules/SearchResults/SearchResultsViewModel.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import FileHound

struct ResultActionControllerTests {
    @Test
    func deleteRenameAndRemoveRefreshViewModelImmediately() throws {
        let first = SearchResultItem(path: "/tmp/a.txt", matchReason: "name", previewSnippet: nil)
        let second = SearchResultItem(path: "/tmp/b.txt", matchReason: "name", previewSnippet: nil)
        let viewModel = SearchResultsViewModel()
        viewModel.items = [first, second]
        let controller = ResultActionController(fileService: .stub, workspace: .stub, confirmationPresenter: { _ in true })

        try controller.handleRename(item: second, newName: "renamed.txt", viewModel: viewModel)
        #expect(viewModel.items.map(\.path).contains("/tmp/renamed.txt"))

        try controller.handleDeleteImmediately(items: [first], viewModel: viewModel)
        #expect(viewModel.items.map(\.path) == ["/tmp/renamed.txt"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/ResultActionControllerTests`

Expected: FAIL because concrete action handlers are incomplete.

- [ ] **Step 3: Write minimal implementation**

```swift
final class ResultActionController {
    func handleRename(item: SearchResultItem, newName: String, viewModel: SearchResultsViewModel) throws {
        let updatedURL = try fileService.renameItem(at: URL(fileURLWithPath: item.path), to: newName)
        viewModel.replaceItems([item.withUpdatedPath(updatedURL.path)])
    }

    func handleDeleteImmediately(items: [SearchResultItem], viewModel: SearchResultsViewModel) throws {
        guard confirmationPresenter(.deleteImmediately(items.count)) else { return }
        try fileService.deleteImmediately(urls: items.map { URL(fileURLWithPath: $0.path) })
        viewModel.removeItems(ids: Set(items.map(\.id)))
    }
}
```

Populate the rest of the menu actions using the same pattern for trash, alias creation, tags, invisibility, unlock, copy path, reveal, get info, quick look, and remove-from-results.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/ResultActionControllerTests -only-testing:FileHoundTests/ResultFileOperationServiceTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add FileHound/Modules/SearchResults/ResultActionController.swift \
  FileHound/Modules/SearchResults/ResultContextMenuFactory.swift \
  FileHound/Modules/SearchResults/ResultFileOperationService.swift \
  FileHound/Modules/SearchResults/SearchResultsViewController.swift \
  FileHound/Modules/SearchResults/SearchResultsViewModel.swift \
  FileHoundTests/SearchResults/ResultActionControllerTests.swift \
  FileHoundTests/SearchResults/ResultFileOperationServiceTests.swift
git commit -m "feat: add finder-style result context actions"
```

### Task 8: Final Verification

**Files:**
- Modify: `FileHoundUITests/*` as needed
- Verify: `docs/superpowers/specs/2026-04-10-filehound-results-actions-design.md`

- [ ] **Step 1: Run focused unit tests**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests`

Expected: PASS

- [ ] **Step 2: Run focused UI tests if automation mode is available**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundUITests`

Expected: PASS, or capture the exact automation-mode failure if the environment still blocks UI automation.

- [ ] **Step 3: Manual smoke checklist**

```text
1. Launch FileHound and confirm the main window title is FileHound.
2. Add rules until the window reaches the top visible edge, then verify the rule area becomes scrollable and the bottom bar remains visible.
3. Run a search, multi-select results, and verify the full context menu appears.
4. Verify Move to Trash removes entries immediately.
5. Verify Delete Immediately asks for confirmation and removes entries on confirm.
6. Verify Rename updates the row inline.
7. Verify grid/table/tree views all show Finder-style icons or thumbnails.
```

- [ ] **Step 4: Commit**

```bash
git add FileHoundUITests docs/superpowers/specs/2026-04-10-filehound-results-actions-design.md
git commit -m "test: verify result actions and adaptive search window"
```

## Self-Review

- Spec coverage: covered result actions, multi-selection, live refresh, icon rendering, and adaptive main-window sizing. No spec section is left without a corresponding task.
- Placeholder scan: the only intentionally compact section is Task 7’s “populate the rest of the menu actions using the same pattern”; expand this inline during implementation if a concrete action needs additional scaffolding. No `TBD` or `TODO` placeholders remain.
- Type consistency: all new names use `ResultActionController`, `ResultFileOperationService`, `ResultIconProvider`, and `SearchWindowLayoutCoordinator`. Keep those exact names during implementation.
