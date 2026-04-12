# FileHound Release Appcast Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a manual-friendly three-step `1.0.0` release pipeline for FileHound that produces a notarized DMG, publishes it to GitHub Releases, and generates a GitHub-backed Sparkle `appcast.xml`.

**Architecture:** Keep the release flow split into three shell scripts under `Scripts/`. `build_dmg.sh` owns workspace archive creation and formal release validation, `publish_github_release.sh` owns GitHub Release creation and asset upload, and `generate_appcast.sh` owns local DMG archives plus repo-root feed generation. Sparkle bundle metadata is configured from XcodeGen project settings so release builds expose the feed URL and EdDSA public key required by `UpdateManager`.

**Tech Stack:** Bash, XcodeGen, Xcode build tools, GitHub CLI/API, Sparkle, Python 3, macOS notarization tools

---

## File Map

- Modify: `Scripts/build_dmg.sh`
  Responsibility: build from `FileHound.xcworkspace`, validate release prerequisites, archive a signed app, generate a versioned DMG, and default to notarize + staple.
- Create: `Scripts/publish_github_release.sh`
  Responsibility: infer repo/tag/title, create or update a GitHub Release, and upload a chosen DMG asset without hiding the manual step boundary.
- Modify: `Scripts/generate_appcast.sh`
  Responsibility: maintain `build/appcast-archives/`, generate Sparkle appcast XML from archived DMGs, and rewrite enclosure URLs to GitHub Release assets.
- Modify: `project.yml`
  Responsibility: define release bundle metadata for `SUFeedURL` and `SUPublicEDKey`.
- Modify: `FileHound.xcodeproj/project.pbxproj`
  Responsibility: sync generated Xcode settings after updating `project.yml`.
- Modify: `README.md`
  Responsibility: document the supported build -> publish -> appcast workflow and the correct `Scripts/` paths.
- Modify: `openspec/changes/build-release-appcast-pipeline/tasks.md`
  Responsibility: mark OpenSpec tasks complete as implementation and verification finish.
- Modify: `appcast.xml`
  Responsibility: store the generated Sparkle feed for committed releases.

### Task 1: Plan the Release Script Boundaries

**Files:**
- Create: `docs/superpowers/plans/2026-04-12-release-appcast-pipeline.md`

- [ ] **Step 1: Capture the implementation plan**

Write this file with the final task decomposition before changing code so each later commit stays scoped to one release capability area.

- [ ] **Step 2: Review the plan against the approved design**

Run: `sed -n '1,260p' docs/superpowers/plans/2026-04-12-release-appcast-pipeline.md`

Expected: the plan explicitly covers DMG build, GitHub Release publishing, appcast generation, Sparkle metadata, docs, and final `1.0.0` verification.

### Task 2: Rebuild the DMG Packaging Step

**Files:**
- Modify: `Scripts/build_dmg.sh`

- [ ] **Step 1: Prove the current script misses the required interface**

Run: `bash Scripts/build_dmg.sh --help`

Expected: the current help is missing the workspace/release-chain details and there is no explicit release-prerequisite validation.

- [ ] **Step 2: Replace the script with a formal release implementation**

Add a script that:

```bash
- reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
- archives from `FileHound.xcworkspace`
- validates `create_pretty_dmg.sh`, `xcodebuild`, `codesign`, and notarization prerequisites
- verifies the built app is signed with `Developer ID Application`
- uses `create_pretty_dmg.sh` to emit a versioned DMG under `build/dmg/`
- notarizes and staples by default, with `--no-notarize` as the local-only opt-out
```

- [ ] **Step 3: Re-run the interface check**

Run: `bash Scripts/build_dmg.sh --help`

Expected: PASS, with documented `--keychain-profile` and `--no-notarize` options plus release-path behavior.

- [ ] **Step 4: Smoke-test the local build path**

Run: `bash Scripts/build_dmg.sh --no-notarize`

Expected: PASS, producing a versioned DMG in `build/dmg/` from `FileHound.xcworkspace`.

- [ ] **Step 5: Commit the packaging work**

```bash
git add Scripts/build_dmg.sh docs/superpowers/plans/2026-04-12-release-appcast-pipeline.md
git commit -m "构建：完善 DMG 打包发布脚本"
```

### Task 3: Add GitHub Release Publication

**Files:**
- Create: `Scripts/publish_github_release.sh`

- [ ] **Step 1: Prove the publication step is missing**

Run: `bash Scripts/publish_github_release.sh --help`

Expected: FAIL because the script does not exist yet.

- [ ] **Step 2: Implement the release publisher**

Add a script that:

```bash
- resolves the latest versioned DMG or accepts `--dmg`
- detects `OWNER/REPO` from Git remotes or accepts `--repo`
- derives `v<version>` tags and `FileHound v<version>` titles
- creates or updates GitHub Releases with `gh release`
- uploads the DMG asset with overwrite support
- keeps appcast generation as a separate later script
```

- [ ] **Step 3: Verify the command interface**

Run: `bash Scripts/publish_github_release.sh --help`

Expected: PASS, with `--dmg`, `--repo`, `--tag`, `--title`, `--notes`, `--notes-file`, and `--generate-notes` documented.

- [ ] **Step 4: Commit the publisher**

```bash
git add Scripts/publish_github_release.sh
git commit -m "发布：增加 GitHub Release 上传脚本"
```

### Task 4: Generate GitHub-Backed Sparkle Appcast and Release Metadata

**Files:**
- Modify: `Scripts/generate_appcast.sh`
- Modify: `project.yml`
- Modify: `FileHound.xcodeproj/project.pbxproj`

- [ ] **Step 1: Prove the current appcast output is a placeholder**

Run: `bash Scripts/generate_appcast.sh && rg -n "example.com" appcast.xml`

Expected: PASS with placeholder `example.com` URLs, proving the script must be replaced.

- [ ] **Step 2: Implement the appcast generator**

Update the script so it:

```bash
- archives a supplied DMG into `build/appcast-archives/`
- locates Sparkle tooling from DerivedData
- requires a Sparkle keychain account and uses `generate_appcast`
- rewrites enclosure URLs to GitHub Release asset URLs
- emits repo-root `appcast.xml`
```

- [ ] **Step 3: Configure Sparkle feed metadata**

Add release settings in `project.yml` for:

```yaml
INFOPLIST_KEY_SUFeedURL: https://raw.githubusercontent.com/wangwanjie/FileHound/main/appcast.xml
INFOPLIST_KEY_SUPublicEDKey: <generated Sparkle public key>
```

Then run: `xcodegen generate`

Expected: PASS, syncing `FileHound.xcodeproj/project.pbxproj` with the new Info.plist keys.

- [ ] **Step 4: Verify the new appcast interface**

Run: `bash Scripts/generate_appcast.sh --help`

Expected: PASS, documenting `--archive`, `--archives-dir`, `--output`, `--repo`, `--account`, and release notes options.

- [ ] **Step 5: Commit the feed work**

```bash
git add Scripts/generate_appcast.sh project.yml FileHound.xcodeproj/project.pbxproj
git commit -m "更新：接入 Sparkle appcast 发布配置"
```

### Task 5: Document and Verify the `1.0.0` Release Flow

**Files:**
- Modify: `README.md`
- Modify: `appcast.xml`
- Modify: `openspec/changes/build-release-appcast-pipeline/tasks.md`

- [ ] **Step 1: Document the supported manual release sequence**

Update `README.md` so it shows:

```bash
./Scripts/build_dmg.sh
./Scripts/publish_github_release.sh
./Scripts/generate_appcast.sh --archive build/dmg/<versioned-file>.dmg
```

and describes prerequisites for `gh`, notarization, and Sparkle keys.

- [ ] **Step 2: Run the full release verification path**

Run:

```bash
bash Scripts/build_dmg.sh
bash Scripts/publish_github_release.sh --generate-notes
bash Scripts/generate_appcast.sh --archive build/dmg/<generated-dmg> --repo wangwanjie/FileHound
```

Expected:
- the DMG is versioned and notarized/stapled
- GitHub Release `v1.0.0` exists with the DMG asset
- `appcast.xml` points to the matching GitHub Release download URL

- [ ] **Step 3: Mark the OpenSpec tasks complete**

Update `openspec/changes/build-release-appcast-pipeline/tasks.md` to check off every completed item.

- [ ] **Step 4: Commit docs and OpenSpec bookkeeping**

```bash
git add README.md appcast.xml openspec/changes/build-release-appcast-pipeline/tasks.md
git commit -m "文档：同步发布流程与 appcast 任务状态"
```
