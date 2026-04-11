## Context

FileHound is already structured around AppKit controllers for the find window, results window, and preferences window, with MMKV-backed storage for a small subset of app settings. That baseline is enough for a parity push, but several core behaviors are still placeholder-level: `SearchWorkflowController` only delivers a final batch of results, `SearchScopeMenuProvider` does not persist recent locations, `SearchPreferencesViewController` is mostly static UI, and `SavedSearchStore` only keeps a name plus summary text instead of reopenable criteria.

The local Find Any File 2.5.5 install confirms the target surface area for this change: FAF-style scope presets and recent locations, show-results-early behavior, results-window reuse, toolbar toggles for invisibles/package contents/trashed items, special folders, previous-search restore, and richer saved-search/history behavior. The implementation needs to stay within the existing Swift 5.10 + AppKit + SnapKit + MMKV stack and remain testable through the current unit and UI test setup.

## Goals / Non-Goals

**Goals:**
- Introduce a persistent search-session model that can drive the find window, results window, search history, and saved searches from the same source of truth.
- Add incremental search/result delivery so `Show Results Early` and live matched-count updates are possible without rewriting the app around a new UI framework.
- Bind General, Search, Appearance, and Updates preferences to real runtime behavior instead of isolated controls.
- Preserve AppKit-native behavior and existing project dependencies while expanding coverage with unit and UI tests.

**Non-Goals:**
- Replicate FAF's remote-server, NAS, or SSH-specific features such as server settings and remote `find` execution.
- Complete privileged-helper parity or a full-disk-access overhaul beyond what current permission diagnostics already support.
- Implement every hidden expert rule from FAF; this change focuses on the visible workflow and settings surfaced by the existing FileHound UI direction.

## Decisions

### 1. Introduce codable parity models and dedicated MMKV-backed stores

FileHound needs first-class models for restorable search criteria and runtime preferences instead of more ad hoc strings and booleans. This change should add codable models for:

- search criteria snapshots
- scope selections and recent locations
- result presentation state
- special-folder rules
- recent searches
- saved searches with full payloads

These models should live behind small repositories or stores so view controllers do not read and write MMKV directly.

Alternative considered:
- Extend `AppSettings` and `SavedSearchStore` with more primitive keys.
- Rejected because parity behavior crosses multiple windows and needs grouped, versionable payloads for restore and migration.

### 2. Move from batch-only search completion to a session coordinator with incremental updates

`SearchWorkflowController` should evolve from a fire-once callback wrapper into a session-oriented controller that can emit:

- search started
- partial result snapshots
- search completed
- search cancelled

A `SearchWindowSessionController` or equivalent coordinator should own the current criteria, results-window relationship, history persistence, and preference-aware execution options. That keeps cross-window behaviors such as `Show Results Early`, `Tie Results window to Find window`, and previous-search restore out of individual views.

Alternative considered:
- Keep the current batch-only executor flow and patch partial behavior into `SearchFormViewController`.
- Rejected because the logic would become duplicated across find and results controllers and would be difficult to test.

### 3. Keep the UI in AppKit, but bind it through view models that reflect FAF parity state

The UI should stay in AppKit/SnapKit, but state ownership needs to move out of raw controls:

- the find window should bind rule rows and scope selection to a parity-aware form model
- the results window should keep one canonical item set and projection state shared by grid, table, and tree views
- preferences segments should bind to store-backed view models so persistence and runtime updates stay consistent

Alternative considered:
- Rebuild parity screens in SwiftUI.
- Rejected because the existing codebase, controllers, and tests are AppKit-based and already close enough to the needed structure.

### 4. Treat search preferences and special folders as execution inputs, not post-processing toggles

Preferences such as `Include Spotlight results`, `Show Results Early`, and special-folder include/exclude rules must feed into the search planner/executor layer. They should be represented as a `SearchExecutionOptions` structure that `SearchPlanBuilder`, `SearchExecutor`, and any scope-selection logic can consume.

Alternative considered:
- Keep preferences purely in the UI layer and filter results after search completion.
- Rejected because that cannot reproduce FAF-style scope behavior, early results, or Spotlight-assisted searching correctly.

### 5. Migrate saved searches without losing existing records

Existing saved searches only store a name and summary. The new format should store full criteria and presentation state, while preserving legacy entries through best-effort migration. Old records should remain visible and either upgrade lazily or open in a limited compatibility mode.

Alternative considered:
- Replace the saved-search data model outright and drop old records.
- Rejected because it creates avoidable user-data loss and makes rollout riskier than necessary.

## Risks / Trade-offs

- [Incremental result delivery increases UI churn] -> Debounce partial updates, keep projection work in `SearchResultsViewModel`, and marshal UI changes onto the main actor.
- [Persisted search/session schemas will evolve over time] -> Add versioned payloads and migration helpers instead of storing unstructured dictionaries.
- [FAF-style visual parity is sensitive to AppKit control metrics] -> Centralize layout constants and verify key states with UI tests plus manual parity checks.
- [Global hotkey activation may require lower-level system APIs] -> Isolate shortcut registration behind a dedicated activation service so the rest of the parity work is not coupled to the implementation detail.
- [Spotlight and special-folder behavior can surface permission or indexing gaps] -> Keep existing diagnostics, tolerate partial results, and fall back to conventional traversal where needed.

## Migration Plan

1. Add new codable stores and default values without removing existing MMKV keys.
2. Upgrade saved-search loading to read both legacy and new payload formats.
3. Rewire search, results, and preferences controllers to use the new session/state abstractions.
4. Extend unit and UI coverage before removing any old bridging logic.

Rollback strategy:
- Preserve legacy keys and stores during rollout so the app can fall back to current behavior without destructive migration.

## Open Questions

- Should this change ship full global hotkey registration, or only the persisted shortcut/activation-mode model if lower-level API work proves too disruptive for the first implementation pass?
