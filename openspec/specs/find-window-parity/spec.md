## ADDED Requirements

### Requirement: The app SHALL present a compact FAF-style find window

The system SHALL present the main search window as a compact AppKit form with a top row containing the search title, scope picker, and `where` label, a middle rule-editing area, and a bottom status/action row. The window SHALL start at a compact height, expand as rule rows are added, and switch the rule area to scrolling before the window exceeds the active screen's visible frame.

#### Scenario: Grow the window when rules fit on screen
- **WHEN** the user adds search rules and the active screen still has vertical space available
- **THEN** the window height increases and the bottom status/action row remains visible

#### Scenario: Switch to scrolling when the screen height is exhausted
- **WHEN** additional rules would push the window outside the active screen's visible frame
- **THEN** the window stays within the visible frame and the rule area becomes scrollable instead of pushing controls off screen

### Requirement: The app SHALL provide FAF-style scope sources

The system SHALL populate the scope picker with preset scopes, recent locations, and visible mounted volumes. The system SHALL support `inside folder...` selection and SHALL replace the scope title with the chosen folder for that selection.

#### Scenario: Pick a custom folder scope
- **WHEN** the user chooses `inside folder...` and confirms a directory
- **THEN** the selected scope stores that directory path and the picker displays the chosen folder name

#### Scenario: Reuse a recent location
- **WHEN** the user completes a search from a custom folder or mounted volume
- **THEN** that location is added to the recent-locations section and is available in the scope picker for later searches

### Requirement: The app SHALL support type-aware multi-rule editing

The system SHALL support multiple rule rows with add/remove controls, field-specific operators, and field-appropriate value editors for visible FAF-aligned criteria. The system SHALL preserve rule order and display the effective logic summary for the current rule set.

#### Scenario: Add another rule row
- **WHEN** the user adds a second rule
- **THEN** a new editable row appears below the existing row and the logic summary reflects multiple conditions

#### Scenario: Edit a toggle-style criterion
- **WHEN** the user changes a rule field to a toggle-style criterion such as `Invisible items`, `Package contents`, or `Trashed contents`
- **THEN** the row replaces free-text entry with the control appropriate for that criterion

### Requirement: The app SHALL expose explicit search-state transitions

The system SHALL transition the find window between idle, editing, and searching states. During searching, the system SHALL disable scope/rule editing, change the primary action from `Find` to `Stop`, and display live status text that includes the active scope and matched-count progress.

#### Scenario: Start a search
- **WHEN** the user starts a search
- **THEN** scope selection and rule editing become disabled, the primary button title becomes `Stop`, and the status row shows the active search scope

#### Scenario: Cancel a search
- **WHEN** the user presses `Stop` during an active search
- **THEN** the search is cancelled, the current criteria remain editable, and the latest known match count stays visible
