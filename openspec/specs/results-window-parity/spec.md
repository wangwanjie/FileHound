# results-window-parity Specification

## Purpose
Define the expected FileHound results-window behavior, including reusable result windows, shared projection controls across views, visible result actions, and grid caption alignment as preview size changes.

## Requirements
### Requirement: The app SHALL manage reusable results windows per search session

The system SHALL reuse an existing results window for repeat searches from the same find-window session, updating the title, matched count, and items in place. The system SHALL honor the results-window tie preference when deciding whether repeated searches remain bound to the originating find window.

#### Scenario: Reuse the current results window
- **WHEN** the user runs another search from a find window whose results window is already open
- **THEN** the existing results window updates in place instead of creating an additional duplicate window

#### Scenario: Show results before the search finishes
- **WHEN** `Show Results Early` is enabled and the search produces matches before completion
- **THEN** the results window opens or refreshes with partial matches and continues updating until the search completes or is cancelled

### Requirement: The app SHALL provide FAF-style results toolbar controls

The system SHALL provide grid, table, and tree view controls; toggles for invisibles, package contents, and trashed items; a Filter field; a preview-size control for grid mode; and sort options for `Name`, `Date Modified`, `Date Created`, `Last Opened`, `Date Added`, `Kind`, `Size`, `Tags`, `Enclosing Folder`, and `Path`.

#### Scenario: Switch between result views
- **WHEN** the user activates grid, table, or tree mode
- **THEN** the selected mode becomes active and the results window keeps the same result set and matched count

#### Scenario: Filter the current projection
- **WHEN** the user enters text in the Filter field
- **THEN** the current results projection is filtered without starting a new filesystem search

### Requirement: The app SHALL share projection state across result views

The system SHALL apply filter text, visibility toggles, sort field, and sort order consistently across grid, table, and tree modes.

#### Scenario: Carry filter state across modes
- **WHEN** the user enters a filter in grid mode and switches to table mode
- **THEN** the table view shows the same filtered subset and matched count

#### Scenario: Keep the chosen sort field active
- **WHEN** the user changes the sort field to `Path` and then switches result modes
- **THEN** the selected sort field remains `Path` and ordering follows path values in the newly selected mode

### Requirement: The app SHALL expose visible FAF-style result actions

The system SHALL expose Finder/FAF-style result actions across all result views, including open, open with, reveal in Finder, move to trash, delete immediately, copy path, get info, rename, quick look, remove from results, and other actions that are applicable to the current selection.

#### Scenario: Remove items from the current result set
- **WHEN** the user invokes `Remove from Results` on selected items
- **THEN** those items disappear from the current result projection without changing the corresponding files on disk

#### Scenario: Confirm destructive deletion
- **WHEN** the user invokes `Delete Immediately` on one or more selected items
- **THEN** the app asks for confirmation before deletion and removes only successfully deleted items from the results list

### Requirement: The app SHALL keep grid result captions centered under previews

The system SHALL keep each grid result item's filename block horizontally centered with its preview icon when the user changes preview size. The system SHALL preserve the current two-line title limit and middle-truncation behavior while applying the updated grid alignment.

#### Scenario: Increase preview size without shifting the caption off center
- **WHEN** the user increases the grid preview size from the default value to a larger supported value
- **THEN** each grid item keeps its filename block horizontally centered with the preview icon

#### Scenario: Reduce preview size without changing title behavior
- **WHEN** the user decreases the grid preview size to a smaller supported value
- **THEN** each grid item still keeps its filename block horizontally centered with the preview icon and continues to display at most two truncated-middle lines
