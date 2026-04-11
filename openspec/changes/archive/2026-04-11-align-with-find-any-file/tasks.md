## 1. Session And Storage Foundations

- [x] 1.1 Add codable parity models for search criteria, scope selection, result presentation state, special folders, recent searches, recent locations, and saved searches
- [x] 1.2 Introduce MMKV-backed stores or repositories for parity models and bridge them from existing `AppSettings` / `SavedSearchStore` entry points
- [x] 1.3 Add migration and compatibility handling for legacy saved-search records and existing primitive preference keys

## 2. Find Window Parity

- [x] 2.1 Rework the find window layout and sizing logic to keep the status/action row visible while growing or scrolling the rule area within the active screen
- [x] 2.2 Expand the scope picker to include preset scopes, recent locations, mounted volumes, and folder-picker updates backed by persistent state
- [x] 2.3 Refactor the rule editor into type-aware multi-row controls with add/remove actions and logic-summary updates
- [x] 2.4 Update search-window state handling so `Find` / `Stop`, disabled editing, and live status text follow explicit idle/editing/searching transitions

## 3. Results Window Parity

- [x] 3.1 Refactor the search workflow/session layer to emit partial result snapshots, matched-count updates, and completion/cancel events
- [x] 3.2 Expand the results toolbar and view model to support the full sort-field list, shared projection state, and preview/filter behavior across grid, table, and tree views
- [x] 3.3 Implement session-aware results-window reuse and honor the tie-results preference when repeating searches
- [x] 3.4 Complete Finder/FAF-style result actions across all result views, including confirmation, refresh, and remove-from-results behavior

## 4. Preferences And Special Folders

- [x] 4.1 Bind General preferences to persistent settings for launch shortcut, activation mode, recent-search menus, previous-search restore, and results-window tie behavior
- [x] 4.2 Bind Search preferences to execution options for expand folders, show results early, include Spotlight results, and special-folder configuration
- [x] 4.3 Add Special Folders management UI and connect its include/exclude/slow-search rules to search planning
- [x] 4.4 Wire Appearance and Updates preferences to live theme/language/update behavior, including restore-defaults flows

## 5. History And Saved Searches

- [x] 5.1 Add recent-search history capture and menu/UI restoration flows backed by the new search-session payloads
- [x] 5.2 Persist recent custom and mounted locations as a deduplicated, size-limited list consumed by the scope picker
- [x] 5.3 Upgrade saved searches to store full criteria and compatible presentation state, then restore them into a find window for editing or rerun

## 6. Verification

- [x] 6.1 Add unit tests for parity stores, migrations, search-session restore, scope/recent-location behavior, result projection state, and special-folder planning
- [x] 6.2 Add UI tests for find-window resizing, search-state transitions, show-results-early behavior, reusable results windows, preference persistence, and saved-search reopen flows
- [x] 6.3 Run the FileHound unit and UI test suites and fix any regressions introduced by the parity changes
