## MODIFIED Requirements

### Requirement: The project SHALL provide a formal DMG release build step

The project SHALL provide a `build_dmg.sh` workflow that builds FileHound from `FileHound.xcworkspace`, accepts an explicit target architecture, and produces one distributable DMG per requested architecture through `create_pretty_dmg.sh`. The default release path SHALL notarize and staple each generated architecture-specific artifact chain before it is treated as publishable.

#### Scenario: Build an arm64 distributable DMG
- **WHEN** the operator runs the DMG build script for an `arm64` release build
- **THEN** the script archives only the `arm64` app, produces an `arm64`-suffixed versioned DMG, and treats notarization plus staple as the default path

#### Scenario: Build an x86_64 distributable DMG
- **WHEN** the operator runs the DMG build script for an `x86_64` release build
- **THEN** the script archives only the `x86_64` app, produces an `x86_64`-suffixed versioned DMG, and treats notarization plus staple as the default path

#### Scenario: Explicitly skip notarization for local-only testing
- **WHEN** the operator passes the documented opt-out flag for notarization
- **THEN** the script still builds the requested architecture-specific DMG but clearly keeps that path separate from the default formal release flow

### Requirement: The project SHALL publish GitHub-backed Sparkle release artifacts

The project SHALL provide a scriptable GitHub Release publishing step and generate architecture-specific Sparkle appcast files whose download URLs point at GitHub Release assets for the corresponding FileHound version. The generated appcast enclosure data SHALL preserve the Sparkle signature attributes required by clients to trust the published update.

#### Scenario: Publish architecture-specific DMGs to GitHub Releases
- **WHEN** the operator runs the release publishing script for `v1.1.1` or a later stable version with both architecture-specific DMGs
- **THEN** the corresponding GitHub Release is created or updated with both architecture-specific assets attached

#### Scenario: Generate architecture-specific appcast entries from archived DMGs
- **WHEN** the operator runs the appcast generation script after publishing or archiving release DMGs for a specific architecture
- **THEN** the generated architecture-specific appcast writes enclosure URLs that target the matching GitHub Release assets for that architecture

#### Scenario: Preserve Sparkle signature metadata in appcast output
- **WHEN** the appcast generation script rewrites feed output for a published release
- **THEN** the resulting enclosure entries retain the Sparkle signature attributes emitted by the upstream generator

### Requirement: Distributed builds SHALL include Sparkle feed metadata

The project SHALL configure distributable FileHound builds with the Sparkle public EdDSA key and an architecture-specific Sparkle feed URL needed by the in-app update manager so each release build participates only in the published update feed for its own architecture.

#### Scenario: arm64 release build exposes the arm64 update feed
- **WHEN** an `arm64` distributable FileHound build is inspected
- **THEN** its bundle metadata includes a valid `SUFeedURL` for the published `arm64` feed and a valid `SUPublicEDKey`

#### Scenario: x86_64 release build exposes the x86_64 update feed
- **WHEN** an `x86_64` distributable FileHound build is inspected
- **THEN** its bundle metadata includes a valid `SUFeedURL` for the published `x86_64` feed and a valid `SUPublicEDKey`
