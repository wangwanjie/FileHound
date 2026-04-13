## Why

The current Special Folders editor is visually cramped and relies on inline per-row removal controls, which makes the window feel unfinished and inefficient once the list grows. The editor now needs a desktop-style list interaction model that matches user expectations for bulk selection, contextual deletion, and drag reordering.

## What Changes

- Add proper content padding so the Special Folders editor no longer places controls directly against the window edges.
- Replace the current bottom `Add Folder…` button and per-row `Remove` button flow with a list control that exposes `+` and `-` actions in the lower-left corner.
- Allow users to add folders, reorder configured rules by drag and drop, and delete one or many selected rows from either the `-` action or a context menu.
- Support multi-selection in the list and apply alternating row backgrounds to improve scanability.
- Preserve existing disposition editing and persistence behavior while moving it into the new list-based presentation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `search-preferences-parity`: change the Special Folders configuration requirements to support padded list presentation, add/remove controls, drag reordering, multi-select deletion, context-menu deletion, and alternating row styling.

## Impact

- Affected code: `FileHound/Modules/Preferences/SearchPreferencesViewController.swift`
- Affected behavior: special-folder rule management inside Search preferences
- Affected tests: debug helpers and UI coverage for the Special Folders editor
