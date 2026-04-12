## Why

FileHound's grid results already expose the preview-size slider, but changing that slider can leave the filename block visibly off-center from the preview icon. This is a narrow regression in a user-facing parity feature, so it should be fixed before more polish work lands on top of the current grid layout.

## What Changes

- Fix grid-mode title rendering so changing preview size keeps the filename block horizontally centered with the preview icon.
- Preserve the current grid preview sizing formula, two-line limit, and middle-truncation behavior while correcting alignment.
- Add regression coverage for grid alignment at multiple preview sizes without changing table or tree behavior.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `results-window-parity`: refine grid preview behavior so filename captions stay horizontally centered with their preview icons as preview size changes.

## Impact

- Affected code is expected in `FileHound/Modules/SearchResults/ResultsCollectionViewController.swift` and, if needed for shared styling helpers, `FileHound/Modules/SearchResults/SearchResultsViewController.swift`.
- Unit test coverage will expand in `FileHoundTests/SearchResults/SearchResultsViewControllerTests.swift`.
- No persistence, search-engine, packaging, or release behavior changes are part of this change.
