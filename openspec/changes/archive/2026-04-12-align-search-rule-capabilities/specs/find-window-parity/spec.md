## MODIFIED Requirements

### Requirement: The app SHALL support type-aware multi-rule editing

The system SHALL support multiple rule rows with add/remove controls, field-specific operators, and field-appropriate value editors for visible FAF-aligned criteria. The system SHALL preserve rule order, display the effective logic summary for the current rule set, and keep unsupported criteria visible in the menus while preventing users from actively selecting them. Date fields SHALL expose FAF-style date operators, and `Kind` SHALL use a dedicated `is / is not + type menu` editor instead of the generic text operator set.

#### Scenario: Add another rule row
- **WHEN** the user adds a second rule
- **THEN** a new editable row appears below the existing row and the logic summary reflects multiple conditions

#### Scenario: Edit a date criterion with FAF-style operators
- **WHEN** the user changes a rule field to `Last modified date`, `Created date`, or `Last opened date`
- **THEN** the row shows the FAF-aligned date operator set and swaps its value editor to match the selected operator

#### Scenario: Edit a kind criterion
- **WHEN** the user changes a rule field to `Kind`
- **THEN** the row shows only `is` and `is not` operators and uses a type picker that includes `any`

#### Scenario: View an unsupported criterion in the menu
- **WHEN** the user opens the field or operator menus for a criterion that is not implemented yet
- **THEN** the unsupported item remains visible but disabled instead of appearing selectable

## ADDED Requirements

### Requirement: The app SHALL validate rule executability before starting a search

The system SHALL validate the current rule set before starting a search and SHALL block search execution when any rule is unsupported or invalid. The system SHALL preserve the user’s current selections, show the blocking reason inline for the affected rule, and surface the first blocking reason in the find window status area.

#### Scenario: Prevent an invalid kind combination
- **WHEN** the user configures `Kind is not any`
- **THEN** the app marks that rule as invalid, disables `Find`, and shows a reason explaining that `Kind is not any` is not allowed

#### Scenario: Prevent an incomplete relative date rule
- **WHEN** the user chooses `is within the last` for a date field but leaves the amount empty or non-positive
- **THEN** the app marks that rule as invalid and does not start the search

#### Scenario: Restore an unsupported rule from saved state
- **WHEN** the app loads a saved or restored rule that maps to an unsupported criterion such as `Comments` or `Script`
- **THEN** the rule remains visible, the app shows that it is not supported yet, and the search stays blocked until the rule is changed or removed
