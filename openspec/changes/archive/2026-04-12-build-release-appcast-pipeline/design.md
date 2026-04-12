## Context

FileHound already contains `UpdateManager` logic that requires `SUFeedURL` and `SUPublicEDKey`, but the project does not yet provide a complete release-distribution chain to feed Sparkle with real published artifacts. The existing scripts are minimal placeholders: `build_dmg.sh` still builds from the project instead of the workspace, `generate_appcast.sh` still points to `example.com`, and there is no fully defined GitHub Release publishing flow.

The approved direction is a manual-friendly, multi-step release process rather than a single monolithic command. The user also explicitly wants the default DMG build path to behave like a real release path, including notarization and staple, and wants the pipeline aligned with the existing `1.0.0` project version.

## Goals / Non-Goals

**Goals:**
- Ship a repeatable three-step release flow for FileHound: build DMG, publish release, generate appcast.
- Make the default DMG build path produce notarized and stapled release artifacts.
- Use GitHub Releases as the download source for Sparkle appcast entries.
- Ensure distributable builds include the Sparkle feed metadata required by `UpdateManager`.

**Non-Goals:**
- Building a GitHub Actions or CI-driven release automation flow.
- Moving appcast hosting to GitHub Pages or another separate static site.
- Designing custom DMG background artwork beyond what `create_pretty_dmg.sh` already provides.
- Converting the workflow into a single all-in-one release script.

## Decisions

### 1. Keep the release flow split into three scripts with explicit handoff points

The project will keep separate scripts for DMG creation, GitHub Release publishing, and appcast generation. The recommended human sequence will be:

1. `scripts/build_dmg.sh`
2. `scripts/publish_github_release.sh`
3. `scripts/generate_appcast.sh`
4. commit and push the updated `appcast.xml`

Why this decision:
- It matches the user's preference for manual-friendly step boundaries.
- It makes it easier to rerun only the failing stage without rebuilding the entire release chain.
- It keeps operational concerns localized instead of growing one script into a brittle workflow engine.

Alternative considered:
- A single umbrella release script that builds, publishes, and rewrites appcast in one pass.
  - Rejected because it reduces operator control and conflicts with the approved workflow style.

### 2. Make `build_dmg.sh` default to a real release path

`build_dmg.sh` should build from `FileHound.xcworkspace`, validate signing, notarize with the default `vanjay_mac_stapler` keychain profile, staple the result, and then produce a versioned DMG through `create_pretty_dmg.sh`.

Why this decision:
- The user explicitly wants notarization and staple to be the default, not an optional extra path.
- FileHound already depends on the workspace entry point in CocoaPods scenarios, so the release script must follow the same rule.

Alternatives considered:
- Keep notarization optional-by-default.
  - Rejected because it makes accidental release of non-distributable artifacts more likely.
- Reimplement HostsEditor's custom DMG background generator.
  - Rejected because the user already approved the simpler `create_pretty_dmg.sh` approach.

### 3. Use GitHub Releases as the canonical download source and repo-root `appcast.xml` as the feed

The generated Sparkle appcast will rewrite enclosure URLs to GitHub Release asset URLs and output `appcast.xml` at the repository root. Release builds should then point `SUFeedURL` at the stable raw GitHub URL for that file.

Why this decision:
- GitHub `origin` is already configured and authenticated locally.
- It avoids adding GitHub Pages or other hosting infrastructure for the first public release.
- It follows the proven pattern already used in HostsEditor.

Alternative considered:
- Use GitHub Pages or a standalone host for the appcast feed.
  - Rejected because it adds infrastructure and operational complexity that the current project does not need.

### 4. Treat Sparkle bundle metadata as part of the release pipeline, not a separate follow-up

This change will include the configuration needed for distributed builds to expose `SUFeedURL` and `SUPublicEDKey`. Without that, the release scripts could succeed while in-app update checks still stay disabled.

Why this decision:
- `UpdateManager` already gates update capability on those values.
- Packaging and update delivery are incomplete if the distributed app cannot discover its own feed.

Alternative considered:
- Defer Sparkle feed metadata to a later preferences/update change.
  - Rejected because it leaves the first public release with a half-wired update pipeline.

## Risks / Trade-offs

- [Notarization depends on credentials and network availability] -> Default to `vanjay_mac_stapler`, validate prerequisites early, and emit actionable failures rather than falling back silently.
- [Release asset URLs and appcast entries can drift out of sync] -> Standardize the operator sequence as build -> release -> appcast -> commit.
- [Versioned DMG naming can break appcast/release matching if inconsistent] -> Derive names from the bundle version in one place and reuse that convention across all scripts.
- [Repo-root appcast updates require an extra git change after every release] -> Accept the manual step because it keeps infrastructure simple and aligns with the approved split-script workflow.

## Migration Plan

1. Upgrade `build_dmg.sh` to use the workspace, formal release signing checks, notarization, staple, and versioned DMG output.
2. Add or expand `publish_github_release.sh` so GitHub Release creation and asset upload are repeatable from local metadata.
3. Replace the placeholder appcast generator with a GitHub-backed Sparkle feed workflow and update the bundle feed metadata accordingly.
4. Use the finished pipeline to publish the first stable `1.0.0` release.

Rollback strategy:
- Revert the updated scripts, bundle metadata, and generated `appcast.xml`, then fall back to local-only DMG generation. No user data migration is involved.

## Open Questions

None.
