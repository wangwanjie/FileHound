## ADDED Requirements

### Requirement: The app SHALL present a FAF-aligned preferences shell

The system SHALL present a non-resizable Preferences window with `General`, `Search`, `Appearance`, and `Updates` segments of equal width, a scrollable content region, and animated height changes that do not move the segmented control.

#### Scenario: Switch preference segments
- **WHEN** the user switches between preference segments
- **THEN** the content area updates, the window height animates to fit the active segment, and the segmented control stays visually anchored

#### Scenario: Exceed the default content height
- **WHEN** a preference segment contains more controls than fit in the default visible area
- **THEN** the content region becomes scrollable instead of resizing the window beyond its defined maximum height

### Requirement: The app SHALL persist and apply general search behavior preferences

The system SHALL persist the launch shortcut, activation mode, `Open Recent Search` menu setting, previous-search restore setting, and results-window tie setting. The system SHALL apply these settings to menu construction, new window creation, and activation behavior without requiring a relaunch.

#### Scenario: Disable the recent-search menu
- **WHEN** the user disables `Open Recent Search`
- **THEN** the app removes or disables the recent-search menu entry the next time menus are rebuilt

#### Scenario: Restore the previous search into a new window
- **WHEN** the user enables previous-search restore and opens a new find window after completing a search
- **THEN** the new window preloads the last saved scope and rule set

### Requirement: The app SHALL persist and apply search execution preferences

The system SHALL persist `Expand all folders when showing results`, `Show Results Early`, `Include Spotlight results`, and Special Folders configuration. The system SHALL apply those settings to search execution and result presentation for subsequent searches.

#### Scenario: Enable early results
- **WHEN** the user enables `Show Results Early` and starts a search
- **THEN** partial matches appear in the results window before the search completes

#### Scenario: Enable Spotlight-assisted searching
- **WHEN** the user enables `Include Spotlight results` and runs a search that can use Spotlight
- **THEN** Spotlight-backed matches are merged into the result set without skipping FileHound's own search pass

### Requirement: The app SHALL persist and apply appearance and update preferences

The system SHALL persist theme, language, results font size, dim color, update-check policy, auto-download choice, and restore-defaults behavior. Changes to theme and language SHALL update open windows immediately.

#### Scenario: Change theme and language
- **WHEN** the user changes theme or language in Preferences
- **THEN** currently open windows update to the new presentation without requiring an app relaunch

#### Scenario: Restore preference defaults
- **WHEN** the user invokes restore-defaults behavior for supported preference groups
- **THEN** the affected settings return to their default values and the UI reflects the reset immediately

### Requirement: The app SHALL provide special-folder configuration UI

The system SHALL let users open a Special Folders configuration UI from Search preferences and manage included, excluded, and slow-search folders used by search planning.

#### Scenario: Add an excluded folder
- **WHEN** the user adds a folder to the excluded special-folders list
- **THEN** later searches omit that folder from traversal unless the search scope explicitly targets it

#### Scenario: Mark a folder as slow-search
- **WHEN** the user marks a configured special folder as slow-search
- **THEN** the search planner stores that override and uses it for later searches that include the folder
