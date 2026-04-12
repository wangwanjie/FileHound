## Why

FileHound already has Sparkle entry points and basic DMG/appcast scripts, but the distribution chain is still incomplete: the DMG build path does not reflect the CocoaPods workspace setup, the appcast script still emits placeholder URLs, and there is no reliable GitHub Release publishing step. Before the first public `1.0.0` release, the project needs a repeatable release pipeline that produces notarized artifacts and a real Sparkle feed.

## What Changes

- Upgrade the release scripts into a three-step pipeline: build a notarized/stapled versioned DMG, publish or update the GitHub Release asset, and generate a GitHub-backed Sparkle appcast.
- Configure release metadata so distributed builds include the Sparkle feed URL and public key required by `UpdateManager`.
- Align the first public release flow with the current project version baseline of `1.0.0` / build `1`.

## Capabilities

### New Capabilities
- `release-distribution-pipeline`: define the supported FileHound release flow for notarized DMGs, GitHub Releases, and Sparkle appcast generation.

### Modified Capabilities
None.

## Impact

- Affected scripts include `scripts/build_dmg.sh`, `scripts/generate_appcast.sh`, and a new or expanded `scripts/publish_github_release.sh`.
- Release metadata changes will touch the app's bundle configuration so Sparkle can read `SUFeedURL` and `SUPublicEDKey` in distributable builds.
- Documentation such as `README.md`, root-level `appcast.xml`, and local release archives under `build/` will become part of the supported release workflow.
