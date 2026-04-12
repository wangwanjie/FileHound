# release-distribution-pipeline Specification

## Purpose
TBD - created by archiving change build-release-appcast-pipeline. Update Purpose after archive.
## Requirements
### Requirement: The project SHALL provide a formal DMG release build step

The project SHALL provide a `build_dmg.sh` workflow that builds FileHound from `FileHound.xcworkspace`, derives versioned output names from the app bundle metadata, and produces a distributable DMG through `create_pretty_dmg.sh`. The default release path SHALL notarize and staple the generated artifact chain before it is treated as publishable.

#### Scenario: Build a distributable DMG from the workspace
- **WHEN** the operator runs the DMG build script for a release build
- **THEN** the script uses `FileHound.xcworkspace`, produces a versioned DMG, and treats notarization plus staple as the default path

#### Scenario: Explicitly skip notarization for local-only testing
- **WHEN** the operator passes the documented opt-out flag for notarization
- **THEN** the script still builds the DMG but clearly keeps that path separate from the default formal release flow

### Requirement: The project SHALL publish GitHub-backed Sparkle release artifacts

The project SHALL provide a scriptable GitHub Release publishing step and generate `appcast.xml` entries whose download URLs point at GitHub Release assets for the corresponding FileHound version.

#### Scenario: Publish a versioned DMG to GitHub Releases
- **WHEN** the operator runs the release publishing script for `v1.0.0` or a later stable version
- **THEN** the corresponding GitHub Release is created or updated with the built DMG attached as an asset

#### Scenario: Generate appcast entries from archived DMGs
- **WHEN** the operator runs the appcast generation script after publishing or archiving a release DMG
- **THEN** the generated `appcast.xml` writes enclosure URLs that target the matching GitHub Release asset

### Requirement: Distributed builds SHALL include Sparkle feed metadata

The project SHALL configure distributable FileHound builds with the Sparkle feed URL and public EdDSA key needed by the in-app update manager so release builds can participate in the published appcast workflow.

#### Scenario: Release build exposes update metadata
- **WHEN** a distributable FileHound build is inspected
- **THEN** its bundle metadata includes valid `SUFeedURL` and `SUPublicEDKey` values for the published update feed

