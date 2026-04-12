## ADDED Requirements

### Requirement: The workspace SHALL launch the main app product for routine development
The repository SHALL provide a stable workspace development entry point that runs `FileHound.app` for normal IDE Run actions, instead of launching `FileHoundHelper` or a Pods-generated target.

#### Scenario: Run the main workspace scheme
- **WHEN** a developer opens `FileHound.xcworkspace` and runs the primary app scheme
- **THEN** Xcode builds and launches `FileHound.app`

### Requirement: The helper target SHALL remain separate from the default UI launch path
The system SHALL keep `FileHoundHelper` available as an auxiliary tool target without making it the default or recommended scheme for bringing up the app UI.

#### Scenario: Open the workspace after project generation
- **WHEN** a developer regenerates the project or opens the workspace on a fresh machine
- **THEN** the default documented UI debugging path uses `FileHound`, and running `FileHoundHelper` is not required to show the main window

### Requirement: The workspace launch configuration SHALL be reproducible from versioned project metadata
The main app launch path SHALL be defined by version-controlled project generation artifacts or shared scheme metadata, not by per-user `xcuserdata` state alone.

#### Scenario: Recreate local project state
- **WHEN** a developer regenerates the Xcode project and reopens `FileHound.xcworkspace`
- **THEN** the `FileHound` run path remains available without manually repairing local user state
