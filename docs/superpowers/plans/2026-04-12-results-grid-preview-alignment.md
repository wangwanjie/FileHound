# FileHound Results Grid Preview Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep grid result captions horizontally centered with their preview icons when `previewSize` changes, without changing table/tree behavior or the current two-line middle-truncation policy.

**Architecture:** Keep the fix inside the grid rendering path by post-processing the existing highlighted attributed title with a centered paragraph style before assigning it to the grid label. Add DEBUG-only inspection hooks in the grid controller and a thin bridge in `SearchResultsViewController` so the existing search-results test file can lock the regression with geometry-based assertions.

**Tech Stack:** Swift, AppKit, SnapKit, Foundation, Testing, xcodebuild, OpenSpec

---

## File Map

- Modify: `FileHound/Modules/SearchResults/ResultsCollectionViewController.swift`
  Responsibility: apply grid-only centered paragraph styling, keep existing layout/truncation settings, and expose DEBUG alignment inspection helpers.
- Modify: `FileHound/Modules/SearchResults/SearchResultsViewController.swift`
  Responsibility: expose controller-level DEBUG accessors so `SearchResultsViewControllerTests` can query grid alignment without reaching into private view-controller state.
- Modify: `FileHoundTests/SearchResults/SearchResultsViewControllerTests.swift`
  Responsibility: add regression tests for grid title alignment at multiple preview sizes and for preserving the two-line middle-truncation policy.
- Modify: `openspec/changes/fix-results-grid-preview-alignment/tasks.md`
  Responsibility: mark the OpenSpec implementation tasks complete once code and verification finish.

### Task 1: Lock the Grid Alignment Regression Contract

**Files:**
- Modify: `FileHoundTests/SearchResults/SearchResultsViewControllerTests.swift`
- Modify: `FileHound/Modules/SearchResults/SearchResultsViewController.swift`
- Modify: `FileHound/Modules/SearchResults/ResultsCollectionViewController.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import AppKit
import Testing
@testable import FileHound

struct SearchResultsViewControllerTests {
    @MainActor
    @Test
    func gridTitlesStayHorizontallyCenteredAcrossPreviewSizes() {
        let item = SearchResultItem(
            path: "/tmp/2026-quarterly-preview-alignment-report.lookin",
            matchReason: "名称命中",
            previewSnippet: "report",
            highlightKind: .name,
            highlightQuery: "report"
        )
        let viewModel = SearchResultsViewModel()
        viewModel.items = [item]
        let controller = SearchResultsViewController(viewModel: viewModel)
        _ = controller.view

        #expect(controller.debugGridTitleParagraphAlignment(for: item, previewSize: 72) == .center)
        #expect(controller.debugGridTitleAlignmentOffset(for: item, previewSize: 72) < 2)
        #expect(controller.debugGridTitleAlignmentOffset(for: item, previewSize: 112) < 2)
    }

    @MainActor
    @Test
    func gridTitlesKeepTwoLineMiddleTruncation() {
        let item = SearchResultItem(
            path: "/tmp/this-is-a-very-very-long-file-name-used-to-lock-grid-preview-caption-behavior.lookin",
            matchReason: "名称命中",
            previewSnippet: "preview",
            highlightKind: .name,
            highlightQuery: "preview"
        )
        let controller = SearchResultsViewController(viewModel: SearchResultsViewModel())
        _ = controller.view

        #expect(controller.debugGridTitleMaximumNumberOfLines == 2)
        #expect(controller.debugGridTitleLineBreakMode == .byTruncatingMiddle)
        #expect(controller.debugGridTitleAlignmentOffset(for: item, previewSize: 48) < 2)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchResultsViewControllerTests`

Expected: FAIL because the new grid DEBUG helpers do not exist yet and the grid title path does not explicitly apply centered paragraph styling.

- [ ] **Step 3: Write the minimal implementation**

```swift
private final class ResultGridItem: NSCollectionViewItem {
    // existing properties...

    private func applyHighlightedTitle() {
        guard let currentItem else {
            return
        }
        titleLabel.attributedStringValue = centeredGridTitle(
            for: currentItem,
            baseColor: isSelected ? .controlAccentColor : .labelColor
        )
    }

    private func centeredGridTitle(for item: SearchResultItem, baseColor: NSColor) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            attributedString: SearchResultNameHighlighter.attributedTitle(for: item, baseColor: baseColor)
        )
        guard attributed.length > 0 else {
            return attributed
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        attributed.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: attributed.length)
        )
        return attributed
    }
}
```

```swift
#if DEBUG
extension ResultsCollectionViewController {
    func debugTitleAlignmentOffset(for item: SearchResultItem, previewSize: CGFloat) -> CGFloat {
        let gridItem = ResultGridItem()
        _ = gridItem.view
        gridItem.view.frame = NSRect(x: 0, y: 0, width: previewSize + 60, height: previewSize + 44)
        gridItem.render(item, iconProvider: iconProvider, previewSize: previewSize)
        gridItem.view.layoutSubtreeIfNeeded()
        return gridItem.debugTitleAlignmentOffset
    }

    func debugTitleParagraphAlignment(for item: SearchResultItem, previewSize: CGFloat) -> NSTextAlignment {
        let gridItem = ResultGridItem()
        _ = gridItem.view
        gridItem.view.frame = NSRect(x: 0, y: 0, width: previewSize + 60, height: previewSize + 44)
        gridItem.render(item, iconProvider: iconProvider, previewSize: previewSize)
        gridItem.view.layoutSubtreeIfNeeded()
        return gridItem.debugTitleParagraphAlignment
    }

    var debugTitleMaximumNumberOfLines: Int {
        let gridItem = ResultGridItem()
        _ = gridItem.view
        return gridItem.debugTitleMaximumNumberOfLines
    }

    var debugTitleLineBreakMode: NSLineBreakMode {
        let gridItem = ResultGridItem()
        _ = gridItem.view
        return gridItem.debugTitleLineBreakMode
    }
}
#endif
```

```swift
#if DEBUG
extension SearchResultsViewController {
    func debugGridTitleAlignmentOffset(for item: SearchResultItem, previewSize: CGFloat) -> CGFloat {
        gridController.debugTitleAlignmentOffset(for: item, previewSize: previewSize)
    }

    func debugGridTitleParagraphAlignment(for item: SearchResultItem, previewSize: CGFloat) -> NSTextAlignment {
        gridController.debugTitleParagraphAlignment(for: item, previewSize: previewSize)
    }

    var debugGridTitleMaximumNumberOfLines: Int {
        gridController.debugTitleMaximumNumberOfLines
    }

    var debugGridTitleLineBreakMode: NSLineBreakMode {
        gridController.debugTitleLineBreakMode
    }
}
#endif
```

```swift
#if DEBUG
extension ResultGridItem {
    var debugTitleParagraphAlignment: NSTextAlignment {
        guard titleLabel.attributedStringValue.length > 0,
              let style = titleLabel.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle else {
            return .left
        }
        return style.alignment
    }

    var debugTitleMaximumNumberOfLines: Int {
        titleLabel.maximumNumberOfLines
    }

    var debugTitleLineBreakMode: NSLineBreakMode {
        titleLabel.lineBreakMode
    }

    var debugTitleAlignmentOffset: CGFloat {
        let iconRect = iconView.convert(iconView.bounds, to: view)
        let labelRect = titleLabel.convert(titleLabel.bounds, to: view)
        let measured = titleLabel.attributedStringValue.boundingRect(
            with: NSSize(width: labelRect.width, height: labelRect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textWidth = min(labelRect.width, ceil(measured.width))
        let textMidX: CGFloat
        switch debugTitleParagraphAlignment {
        case .center:
            textMidX = labelRect.minX + floor((labelRect.width - textWidth) / 2) + (textWidth / 2)
        case .right:
            textMidX = labelRect.maxX - (textWidth / 2)
        default:
            textMidX = labelRect.minX + (textWidth / 2)
        }
        return abs(iconRect.midX - textMidX)
    }
}
#endif
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchResultsViewControllerTests`

Expected: PASS

- [ ] **Step 5: Commit the code and regression tests**

```bash
git add FileHound/Modules/SearchResults/ResultsCollectionViewController.swift \
  FileHound/Modules/SearchResults/SearchResultsViewController.swift \
  FileHoundTests/SearchResults/SearchResultsViewControllerTests.swift
git commit -m "修复：校正 grid 预览尺寸下的标题居中"
```

### Task 2: Sync OpenSpec State and Final Verification

**Files:**
- Modify: `openspec/changes/fix-results-grid-preview-alignment/tasks.md`

- [ ] **Step 1: Mark the implementation and regression tasks complete in OpenSpec**

```md
## 1. Grid Alignment Fix

- [x] 1.1 Update grid item title rendering so attributed filenames keep centered paragraph styling in grid mode only
- [x] 1.2 Preserve the existing preview-size sizing math, two-line limit, and middle truncation while applying the alignment fix

## 2. Regression Coverage

- [x] 2.1 Add DEBUG inspection helpers needed to measure grid icon/title horizontal alignment in tests
- [x] 2.2 Extend search-results tests to verify grid alignment at multiple preview sizes and with a long highlighted filename

## 3. Verification

- [ ] 3.1 Run the targeted search-results test suite and confirm the new grid alignment coverage passes
```

- [ ] **Step 2: Run the targeted verification suite from the workspace**

Run: `xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchResultsViewControllerTests`

Expected: PASS, including the new grid alignment regression tests.

- [ ] **Step 3: Mark the verification task complete and confirm the change is apply-complete**

```md
## 3. Verification

- [x] 3.1 Run the targeted search-results test suite and confirm the new grid alignment coverage passes
```

```bash
openspec status --change "fix-results-grid-preview-alignment" --json
```

Expected: `progress.complete` equals `5` and every artifact remains `done`.

- [ ] **Step 4: Commit the OpenSpec bookkeeping**

```bash
git add openspec/changes/fix-results-grid-preview-alignment/tasks.md
git commit -m "文档：同步 grid 预览尺寸对齐变更任务状态"
```
