## Context

The current Special Folders editor builds its contents with a vertical `NSStackView` of custom row views and places the add button directly beneath the list. That structure makes the content feel flush with the window edges and does not provide native support for multi-selection, drag reordering, or contextual actions. The change is localized to the Search preferences module, but it benefits from an explicit design because the requested interactions map more cleanly to AppKit table patterns than to the current stack-based layout.

## Goals / Non-Goals

**Goals:**

- Present the configured rules inside a padded, table-style editor that reads like a native macOS list.
- Support adding folders from a lower-left `+` control and deleting one or many selected rows from either a lower-left `-` control or a context menu.
- Support drag reordering while preserving the existing rule model and disposition choices.
- Improve scanability with alternating row backgrounds without changing how rules are stored or consumed by the search planner.

**Non-Goals:**

- Changing the underlying `SpecialFoldersConfiguration` model or search-planning semantics.
- Adding inline path editing, batch disposition editing, or validation beyond the current folder-picker flow.
- Redesigning the surrounding Search preferences screen outside the Special Folders editor window.

## Decisions

### Use `NSTableView` inside an `NSScrollView` for the editor body

`NSTableView` provides native multi-selection, row reordering hooks, context menus, and alternating row backgrounds. Reusing the current `NSStackView` row composition would require custom selection, hit testing, and drag/drop bookkeeping, which is higher risk for a preferences-only UI.

Alternative considered: keep custom row views inside a stack or collection container. Rejected because it would recreate behavior AppKit already provides and make multi-select deletion significantly more fragile.

### Move add/remove actions into a lower-left control strip

The editor will expose compact `+` and `-` controls anchored to the lower-left edge of the list area, matching the requested interaction and common AppKit list editing conventions. The `+` action will continue to open `NSOpenPanel`; the `-` action will operate on the current selection and disable when nothing is selected.

Alternative considered: toolbar or trailing action buttons. Rejected because the request explicitly calls for lower-left controls and because those placements separate actions from the list they affect.

### Keep disposition editing in-row and persist after every mutation

Each row will continue to expose the disposition selector so users can adjust include/exclude/slow-search without opening a secondary editor. Add, remove, reorder, and disposition updates will all save the full configuration immediately through the existing store, preserving current persistence expectations.

Alternative considered: split editing into a detail pane. Rejected because it adds complexity without solving a user-reported problem.

### Scope contextual deletion to the active selection

The right-click menu will offer deletion using the current selection. If the user right-clicks an unselected row, the editor should first make that row the selection before showing the menu so the delete action remains predictable and still supports multi-select when the existing selection is preserved.

Alternative considered: always delete only the clicked row from the context menu. Rejected because it conflicts with the requested multi-select delete support.

## Risks / Trade-offs

- [Table-based UI is more complex than the current stack view] → Keep the implementation isolated inside the Special Folders editor controller and reuse the existing model/store APIs.
- [Immediate persistence can make reorder/delete mistakes feel permanent] → Rely on standard selection and drag behaviors, and keep destructive actions scoped to explicit user input from `-` or the context menu.
- [Context-menu selection behavior can be unintuitive] → Align with native AppKit expectations by updating selection on right-click when needed before presenting the menu.

## Migration Plan

No data migration is required. Existing saved rules remain valid because the model and storage key do not change. The rollout is limited to replacing the editor presentation and interaction wiring in the preferences module.

## Open Questions

- None. The requested interaction model is specific enough to implement directly.
