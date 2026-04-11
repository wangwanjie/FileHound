## Why

FileHound has the right overall direction, but the current app still stops at partial parity with Find Any File: the find window is a skeleton, the results window only covers a subset of FAF's visible controls, preference toggles are mostly not wired into runtime behavior, and saved searches do not preserve enough state to repeat a search faithfully. With Find Any File 2.5.5 installed locally as the reference, this is the right point to define the parity contract before implementation spreads further.

## What Changes

- Rebuild the main find window so its layout, scope picker, rule editor, and idle/searching transitions match Find Any File's visible behavior.
- Expand the results window to cover FAF-style view switching, filter and sort controls, progress behavior, reusable result windows, and result actions.
- Turn Search, General, Appearance, and Updates preferences from static UI into persistent settings that change runtime behavior.
- Add FAF-style recent search history, recent locations, previous-search restore, and saved-search reopening so searches can be repeated without rebuilding criteria by hand.

## Capabilities

### New Capabilities
- `find-window-parity`: Align the main search window, scope menu, search rules, and search-state transitions with Find Any File.
- `results-window-parity`: Align the results window views, toolbar behavior, progress updates, and visible result actions with Find Any File.
- `search-preferences-parity`: Persist and apply FAF-style General, Search, Appearance, Updates, and Special Folders settings.
- `search-history-and-saved-searches`: Persist recent searches, recent locations, previous search state, and reopenable saved searches.

### Modified Capabilities

None.

## Impact

- Affected code spans `FileHound/Modules/SearchWindow`, `FileHound/Modules/SearchRules`, `FileHound/Modules/SearchResults`, `FileHound/Modules/Preferences`, `FileHound/Common/Storage`, and `FileHound/SearchEngine`.
- New persistence models are needed for search history, recent locations, special-folder rules, window reuse preferences, and richer saved-search payloads.
- Unit and UI tests need broader coverage for search-state restoration, toolbar behavior, preferences wiring, and repeatable saved-search flows.
