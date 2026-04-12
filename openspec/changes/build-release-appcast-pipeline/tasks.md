## 1. Release Build Script

- [x] 1.1 Upgrade `scripts/build_dmg.sh` to build from `FileHound.xcworkspace`, derive versioned output names, and call `create_pretty_dmg.sh`
- [x] 1.2 Make notarization and staple the default formal release path, with an explicit opt-out flag for local-only testing
- [x] 1.3 Validate signing/notarization prerequisites and emit actionable errors when release prerequisites are missing

## 2. Release Publication And Feed

- [x] 2.1 Add or expand `scripts/publish_github_release.sh` so it can create/update GitHub Releases and upload the built DMG asset
- [x] 2.2 Replace the placeholder `scripts/generate_appcast.sh` flow with a GitHub-backed Sparkle appcast generator that archives DMGs locally and emits root-level `appcast.xml`
- [x] 2.3 Configure the distributable app bundle with `SUFeedURL` and `SUPublicEDKey` so Sparkle can consume the generated feed

## 3. Docs And First Release Verification

- [x] 3.1 Update release documentation to show the supported step-by-step workflow and correct workspace/script paths
- [x] 3.2 Use the finished scripts to validate the `1.0.0` release path end to end, including versioned DMG output, GitHub Release publication, and appcast generation
