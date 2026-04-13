## MODIFIED Requirements

### Requirement: The app SHALL persist and apply appearance and update preferences

The system SHALL persist theme, language, results font size, dim color, update-check policy, auto-download choice, and restore-defaults behavior. Changes to theme and language SHALL update open windows immediately. The Updates preferences pane SHALL reflect the runtime availability of update checking, allow users to trigger a manual check when update checking is available, and present a disabled state instead of attempting an update when required feed metadata is missing.

#### Scenario: Change theme and language
- **WHEN** the user changes theme or language in Preferences
- **THEN** currently open windows update to the new presentation without requiring an app relaunch

#### Scenario: Trigger a manual update check from Preferences
- **WHEN** the user opens the Updates preferences pane and update checking is available
- **THEN** the `Check Now` control is enabled and can trigger the shared application update-check action

#### Scenario: Show update-unavailable state in Preferences
- **WHEN** the user opens the Updates preferences pane and runtime update prerequisites are missing
- **THEN** the `Check Now` control remains disabled and the pane presents an explanatory unavailable state

#### Scenario: Restore preference defaults
- **WHEN** the user invokes restore-defaults behavior for supported preference groups
- **THEN** the affected settings return to their default values and the UI reflects the reset immediately
