## ADDED Requirements

### Requirement: The app SHALL persist recent searches with restorable criteria

The system SHALL record recent searches with a display title, execution time, scope information, and full restorable search criteria. The app SHALL use the same history source for the recent-search menu and any recent-search UI surface.

#### Scenario: Add a completed search to history
- **WHEN** a search completes successfully
- **THEN** the app records a history entry containing the executed criteria and a user-facing title

#### Scenario: Reopen a recent search
- **WHEN** the user chooses an item from recent-search history
- **THEN** the app restores the saved criteria into a find window and makes the search ready to rerun

### Requirement: The app SHALL persist recent locations as a deduplicated list

The system SHALL store recent custom and mounted search locations as a deduplicated, size-limited list that feeds the find-window scope picker.

#### Scenario: Repeat a custom folder search
- **WHEN** the user runs multiple searches from the same custom folder
- **THEN** that folder appears only once in recent locations and moves to the newest position

#### Scenario: Enforce the recent-location limit
- **WHEN** the stored recent-location count exceeds the configured limit
- **THEN** the oldest excess locations are discarded while newer ones remain available

### Requirement: The app SHALL save named searches with full query payloads

The system SHALL save named searches with enough information to restore scope, all rule rows, and compatible result-presentation state. Selecting a saved search SHALL reopen those criteria for editing or rerunning.

#### Scenario: Save and reopen a named search
- **WHEN** the user saves the current search with a name and later selects it from the saved-search UI
- **THEN** the app restores the saved scope and every stored rule row into a find window

#### Scenario: Update saved-search presentation state
- **WHEN** the user saves a search while a result view mode or sort field is active
- **THEN** the saved record stores compatible presentation preferences for the next reopen

### Requirement: The app SHALL preserve legacy saved-search records during migration

The system SHALL continue to display existing summary-only saved searches and SHALL upgrade them lazily or open them in a clearly limited compatibility mode instead of discarding them.

#### Scenario: Load a legacy saved search
- **WHEN** the app reads a saved-search record that only contains legacy summary fields
- **THEN** the record remains visible and the app either upgrades it with defaults or identifies it as limited compatibility
