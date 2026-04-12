## Context

The results window already applies preview-size changes only to `ResultsCollectionViewController`, where each grid item renders a centered icon and a full-width title label below it. The label content comes from `SearchResultNameHighlighter.attributedTitle(...)`, which returns highlighted attributed text without an explicit paragraph alignment. In AppKit, once the grid label uses `attributedStringValue`, the control-level `alignment = .center` is not enough to guarantee that the rendered text block stays visually centered as wrapping and truncation are recalculated for different preview sizes.

The same highlighter is also used by table and tree result views. Those views already have alignment-focused regression tests and should keep their current Finder-style name-column behavior. That makes this a grid-only rendering fix rather than a global text-highlighting change.

## Goals / Non-Goals

**Goals:**
- Keep grid result captions horizontally centered with their preview icons across the supported preview-size range.
- Preserve the current preview-size layout formula, two-line title limit, and middle truncation behavior.
- Add deterministic regression coverage for the grid alignment behavior.

**Non-Goals:**
- Changing table or tree result alignment behavior.
- Retuning grid spacing, item-size math, or thumbnail-loading strategy.
- Introducing snapshot testing or redesigning the grid item visuals.

## Decisions

### 1. Apply centered paragraph styling only in the grid title-rendering path

The fix should be isolated to `ResultGridItem` (or a grid-only helper it uses). The grid item will start from the existing highlighted attributed title, then apply a centered paragraph style across the full string before assigning it to the label.

Why this decision:
- It addresses the actual rendering gap: the attributed title lacks explicit centering information.
- It avoids changing the default output of `SearchResultNameHighlighter`, which would risk regressing table and tree views.

Alternatives considered:
- Change `SearchResultNameHighlighter` globally to emit centered paragraph styling by default.
  - Rejected because the helper is shared by table and tree views that should remain left-aligned.
- Adjust only the title label constraints or width.
  - Rejected because layout changes alone do not fix the missing paragraph-style alignment in the attributed text.

### 2. Keep the existing grid layout and text-overflow policy intact

This change will not alter the existing preview-size bounds, flow-layout item sizing formula, or title-label line-break settings. The goal is to correct title rendering alignment, not to retune the overall grid appearance.

Why this decision:
- The current bug is about alignment drift, not spacing or item density.
- A narrowly scoped fix reduces the risk of introducing unrelated visual regressions.

Alternative considered:
- Rebalance item width, title insets, or icon/title spacing at the same time.
  - Rejected because it expands scope beyond the approved bugfix and would make regressions harder to isolate.

### 3. Add a lightweight DEBUG alignment metric for tests

Grid alignment should be verified with deterministic geometry/assertion helpers rather than screenshot comparisons. A DEBUG-only inspection path can render a grid item in isolation and report the horizontal offset between the icon center and the title's rendered center, or expose equivalent information needed by tests.

Why this decision:
- Existing table and tree tests already use small geometry helpers for alignment checks.
- The same pattern keeps the new regression coverage cheap and stable.

Alternative considered:
- Add snapshot tests for the entire grid view.
  - Rejected because the repo does not use snapshot infrastructure today, and this bug can be covered with simpler assertions.

## Risks / Trade-offs

- [Paragraph-style merging could overwrite future paragraph-specific formatting] -> Apply only the minimal centered paragraph style in the grid path and leave the shared highlighter's default output untouched.
- [Async thumbnail reloads could make layout-based tests flaky] -> Base tests on immediate cell layout and attributed-title properties rather than waiting for async thumbnails.
- [Very long filenames can still look visually dense even when centered] -> Preserve the current two-line middle-truncation behavior and cover long-name cases in regression tests.

## Migration Plan

1. Add the grid-only centered-title rendering change and DEBUG inspection hooks.
2. Add regression tests for at least two preview sizes and a long-name case.
3. Run the targeted search-results test suite before implementation is considered complete.

Rollback strategy:
- Revert the grid-only title styling changes; there is no persisted data or schema migration involved.

## Open Questions

None.
