## ADDED Requirements

### Requirement: The app SHALL provide a unified manual update-check command

The system SHALL expose a single update-check action through both the application menu and the Updates preferences pane. Both entry points SHALL use the same runtime availability state and SHALL trigger the same update manager action.

#### Scenario: Trigger update check from the application menu
- **WHEN** the user chooses `Check for Updates...` from the application menu and update checking is available
- **THEN** the system starts the shared update-check action without requiring the user to open Preferences

#### Scenario: Trigger update check from Preferences
- **WHEN** the user activates `Check Now` in the Updates preferences pane and update checking is available
- **THEN** the system invokes the same shared update-check action used by the application menu

#### Scenario: Disable manual update commands when runtime prerequisites are missing
- **WHEN** the application does not have the runtime metadata required to check for updates
- **THEN** the manual update commands remain unavailable instead of attempting a partial update flow

### Requirement: The app SHALL honor the configured update policy at launch

The system SHALL apply the persisted update-check policy to the running update subsystem during application launch. A policy that enables launch-time checks SHALL trigger an update check after the updater is ready, while a manual-only policy SHALL not trigger an automatic launch check.

#### Scenario: Check on launch when enabled
- **WHEN** the persisted update policy is configured to check on launch and runtime update prerequisites are available
- **THEN** the application performs an update check during startup

#### Scenario: Skip launch-time check in manual mode
- **WHEN** the persisted update policy is configured for manual-only checks
- **THEN** the application completes startup without automatically checking for updates
