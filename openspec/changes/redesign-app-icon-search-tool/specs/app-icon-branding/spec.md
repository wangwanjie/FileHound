## ADDED Requirements

### Requirement: The app SHALL ship a search-focused macOS app icon set

The system SHALL ship a complete macOS AppIcon asset set whose primary visual message is "professional file search." The icon SHALL include an obvious magnifier and a secondary file/result-hit structure so the product does not read as a generic search utility.

#### Scenario: Build uses the replaced app icon assets
- **WHEN** the app is built from the asset catalog
- **THEN** every required AppIcon slot resolves from the checked-in FileHound icon set without missing-icon warnings

#### Scenario: The icon expresses file search rather than generic utility branding
- **WHEN** the icon is reviewed in Finder, the Dock, or Launchpad
- **THEN** the dominant read is a search tool with an obvious magnifier and file-search context

### Requirement: The app SHALL keep the icon recognizable at small macOS sizes

The system SHALL keep the new app icon recognizable at the smallest standard macOS sizes by preserving the large-shape magnifier silhouette and a clear search-hit detail even when fine texture is reduced.

#### Scenario: Small icon sizes remain legible
- **WHEN** the 16x16 and 32x32 icon slots are reviewed
- **THEN** the magnifier silhouette remains identifiable and the icon does not collapse into an unreadable blob
