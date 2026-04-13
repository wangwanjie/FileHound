## MODIFIED Requirements

### Requirement: The app SHALL provide special-folder configuration UI

The system SHALL let users open a Special Folders configuration UI from Search preferences and manage included, excluded, and slow-search folders used by search planning through a padded list editor with alternating row backgrounds, lower-left add/remove controls, multi-row selection, contextual deletion, and drag reordering.

#### Scenario: View configured folders in a padded list

- **WHEN** the user opens the Special Folders window
- **THEN** the editor shows the configured rules inside a list with visible content padding from the window edges, alternating row backgrounds, and lower-left `+` and `-` controls

#### Scenario: Add a folder from the list controls

- **WHEN** the user activates the `+` control and chooses a folder
- **THEN** the system appends that folder to the special-folders list, keeps disposition editing available for the new row, and persists the updated configuration

#### Scenario: Delete selected folders from the remove control

- **WHEN** the user selects one or more rows and activates the `-` control
- **THEN** the system removes all selected rules from the list and persists the updated configuration

#### Scenario: Delete selected folders from a context menu

- **WHEN** the user opens the context menu for a selected row set and chooses the delete action
- **THEN** the system removes the selected rules from the list and persists the updated configuration

#### Scenario: Reorder folders by drag and drop

- **WHEN** the user drags a configured folder row to a new position in the list
- **THEN** the system updates the displayed order, persists that order, and uses it for subsequent special-folder editing sessions
