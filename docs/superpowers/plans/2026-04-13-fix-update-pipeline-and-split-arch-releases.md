# FileHound Update Pipeline And Split-Arch Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair FileHound's Sparkle update flow so the app can reliably check for updates from Preferences and the main menu, then ship `arm64` and `x86_64` as separate notarized release artifacts with architecture-specific appcasts.

**Architecture:** Keep `UpdateManager` as the single runtime coordinator for update availability, update commands, and launch-time policy sync. Keep the release pipeline split into `Scripts/build_dmg.sh`, `Scripts/publish_github_release.sh`, and `Scripts/generate_appcast.sh`, but add an explicit architecture dimension so each build writes its own feed URL, DMG asset, and appcast output.

**Tech Stack:** Swift, AppKit, Sparkle, Swift Testing, XCTest UI tests, Bash, XcodeGen, GitHub CLI, Python 3, macOS notarization tools

---

## File Map

- Modify: `FileHound/Common/Services/UpdateManager.swift`
  Responsibility: centralize update availability, Sparkle startup, launch-time policy sync, and the shared manual update action.
- Modify: `FileHound/App/AppDelegate.swift`
  Responsibility: route launch-time update checks and expose a selector for the shared menu-driven update action.
- Modify: `FileHound/App/MainMenuBuilder.swift`
  Responsibility: add the application-menu update item and bind it to the shared runtime action/state.
- Modify: `FileHound/Modules/Preferences/UpdatePreferencesViewController.swift`
  Responsibility: bind the Preferences pane button state and tooltip to the shared update manager.
- Modify: `FileHound/Resources/Localization/en.lproj/Localizable.strings`
  Responsibility: add or update the update-menu and availability messaging strings.
- Modify: `FileHound/Resources/Localization/zh-Hans.lproj/Localizable.strings`
  Responsibility: localize the new update-menu and availability messaging strings for Simplified Chinese.
- Modify: `FileHound/Resources/Localization/zh-Hant.lproj/Localizable.strings`
  Responsibility: localize the new update-menu and availability messaging strings for Traditional Chinese.
- Create: `FileHoundTests/App/UpdateManagerTests.swift`
  Responsibility: verify runtime update availability, launch policy behavior, and shared update actions without needing a real Sparkle feed.
- Modify: `FileHoundTests/App/MainMenuBuilderTests.swift`
  Responsibility: prove the application menu contains the update entry and reflects availability state.
- Modify: `FileHoundUITests/UpdatePreferencesSmokeTests.swift`
  Responsibility: keep the Updates pane smoke test covering the shared update command UI.
- Modify: `Scripts/build_dmg.sh`
  Responsibility: build one architecture at a time and produce architecture-specific notarized DMGs.
- Modify: `Scripts/generate_appcast.sh`
  Responsibility: generate `appcast-arm64.xml` and `appcast-x86_64.xml` while preserving Sparkle enclosure signature fields.
- Modify: `Scripts/publish_github_release.sh`
  Responsibility: publish one release version with both architecture-specific DMG assets.
- Modify: `openspec/changes/fix-update-pipeline-and-split-arch-releases/tasks.md`
  Responsibility: mark the OpenSpec implementation checklist complete as work lands.
- Modify: `README.md`
  Responsibility: document the architecture-specific release workflow and one-time manual-upgrade caveat for broken legacy builds.

### Task 1: Add a testable shared update runtime

**Files:**
- Create: `FileHoundTests/App/UpdateManagerTests.swift`
- Modify: `FileHound/Common/Services/UpdateManager.swift`

- [ ] **Step 1: Write failing tests for update availability and launch policy**

Create `FileHoundTests/App/UpdateManagerTests.swift` with cases like:

```swift
import Testing
@testable import FileHound

struct UpdateManagerTests {
    @Test
    func canCheckForUpdatesRequiresVersionMetadataFeedAndRuntimeSupport() {
        let manager = UpdateManager(
            settings: AppSettings(storage: InMemoryKeyValueStore()),
            bundleInfo: .init(
                shortVersion: "1.1.1",
                buildVersion: "3",
                feedURL: "https://example.com/appcast-arm64.xml",
                publicKey: "test-public-key"
            ),
            sparkleDriver: StubSparkleDriver(canCheckForUpdates: true)
        )

        #expect(manager.canCheckForUpdates == true)
    }

    @Test
    func shouldCheckOnLaunchRespectsManualOnlyPolicy() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        settings.updateCheckPolicy = .manualOnly

        let manager = UpdateManager(
            settings: settings,
            bundleInfo: .validFixture,
            sparkleDriver: StubSparkleDriver(canCheckForUpdates: true)
        )

        #expect(manager.shouldCheckOnLaunch() == false)
    }
}
```

- [ ] **Step 2: Run the new tests and confirm they fail for the current implementation**

Run: `xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/UpdateManagerTests`

Expected: FAIL because `UpdateManager` does not yet support test injection for bundle metadata and Sparkle runtime state.

- [ ] **Step 3: Add runtime seams and shared availability logic**

Refactor `UpdateManager.swift` around a small injected surface:

```swift
protocol SparkleUpdateDriving {
    var canCheckForUpdates: Bool { get }
    func startUpdaterIfNeeded()
    func checkForUpdates(_ sender: Any?)
    func apply(policy: UpdateCheckPolicy, automaticallyDownloadsUpdates: Bool)
}

struct UpdateBundleInfo {
    let shortVersion: String?
    let buildVersion: String?
    let feedURL: String?
    let publicKey: String?
}

final class UpdateManager: NSObject {
    var unavailableReason: String? {
        guard bundleInfo.feedURL?.isEmpty == false else { return L10n.string("preferences.update.feed_missing") }
        guard bundleInfo.publicKey?.isEmpty == false else { return L10n.string("preferences.update.feed_missing") }
        guard sparkleDriver.canCheckForUpdates else { return L10n.string("preferences.update.feed_missing") }
        return nil
    }
}
```

- [ ] **Step 4: Sync launch policy into the update runtime**

Update `UpdateManager` so the shared runtime exposes one method that both applies policy and optionally triggers launch-time checks:

```swift
func configureForLaunch() {
    sparkleDriver.startUpdaterIfNeeded()
    sparkleDriver.apply(
        policy: settings.updateCheckPolicy,
        automaticallyDownloadsUpdates: settings.autoDownloadUpdates
    )
}

func shouldCheckOnLaunch() -> Bool {
    settings.updateCheckPolicy == .onLaunch && canCheckForUpdates
}
```

- [ ] **Step 5: Re-run the unit tests**

Run: `xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/UpdateManagerTests`

Expected: PASS, covering available and unavailable update runtime states plus launch policy behavior.

- [ ] **Step 6: Commit the runtime refactor**

```bash
git add FileHound/Common/Services/UpdateManager.swift FileHoundTests/App/UpdateManagerTests.swift
git commit -m "更新：统一应用内更新运行时"
```

### Task 2: Wire Preferences and the app menu to the shared update action

**Files:**
- Modify: `FileHound/App/AppDelegate.swift`
- Modify: `FileHound/App/MainMenuBuilder.swift`
- Modify: `FileHound/Modules/Preferences/UpdatePreferencesViewController.swift`
- Modify: `FileHound/Resources/Localization/en.lproj/Localizable.strings`
- Modify: `FileHound/Resources/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `FileHound/Resources/Localization/zh-Hant.lproj/Localizable.strings`
- Modify: `FileHoundTests/App/MainMenuBuilderTests.swift`
- Modify: `FileHoundUITests/UpdatePreferencesSmokeTests.swift`

- [ ] **Step 1: Add failing menu and Preferences tests**

Extend the existing tests with expectations like:

```swift
@MainActor
@Test
func appMenuIncludesCheckForUpdatesItem() throws {
    let menu = MainMenuBuilder().build()
    let appMenu = try #require(menu.item(at: 0)?.submenu)

    #expect(appMenu.items.contains { $0.title == "Check for Updates…" })
}
```

and:

```swift
func testUpdatesTabShowsEnabledCheckNowButtonWhenUpdateRuntimeIsAvailable() throws {
    let app = XCUIApplication()
    AppLaunchHelper.prepareForLaunch(app)
    app.launchArguments = [
        "--uitesting",
        "--open-preferences-on-launch",
        "--open-updates-preferences-on-launch"
    ]
    app.launch()

    XCTAssertTrue(app.buttons["CheckNowButton"].waitForExistence(timeout: 2))
}
```

- [ ] **Step 2: Run the focused tests to confirm the new behavior is missing**

Run:

```bash
xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/MainMenuBuilderTests
xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundUITests/UpdatePreferencesSmokeTests
```

Expected:
- the menu test fails because there is no update menu item
- the UI smoke test still only proves the old button exists, not that it is wired to shared state

- [ ] **Step 3: Route both UI entry points through `UpdateManager`**

Update the application layer to use one action:

```swift
@objc
func checkForUpdates(_ sender: Any?) {
    UpdateManager.shared.checkForUpdates(sender)
}
```

and add the app-menu item:

```swift
let checkForUpdatesItem = NSMenuItem(
    title: L10n.string("menu.check_for_updates"),
    action: #selector(AppDelegate.checkForUpdates(_:)),
    keyEquivalent: ""
)
checkForUpdatesItem.target = target
checkForUpdatesItem.isEnabled = UpdateManager.shared.canCheckForUpdates
appMenu.addItem(checkForUpdatesItem)
```

- [ ] **Step 4: Update the Preferences pane and localized strings**

Bind the button directly to shared runtime state:

```swift
checkNowButton.target = updateManager
checkNowButton.action = #selector(UpdateManager.checkForUpdates(_:))
checkNowButton.isEnabled = updateManager.canCheckForUpdates
checkNowButton.toolTip = updateManager.unavailableReason
```

Add localization keys like:

```text
"menu.check_for_updates" = "Check for Updates…";
"preferences.update.feed_missing" = "Update feed is not configured in this build.";
```

- [ ] **Step 5: Re-run the focused tests**

Run:

```bash
xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/MainMenuBuilderTests
xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundUITests/UpdatePreferencesSmokeTests
```

Expected: PASS, with the menu item present and the Updates pane still loading the shared check-now control.

- [ ] **Step 6: Commit the UI and menu wiring**

```bash
git add FileHound/App/AppDelegate.swift FileHound/App/MainMenuBuilder.swift FileHound/Modules/Preferences/UpdatePreferencesViewController.swift FileHound/Resources/Localization/en.lproj/Localizable.strings FileHound/Resources/Localization/zh-Hans.lproj/Localizable.strings FileHound/Resources/Localization/zh-Hant.lproj/Localizable.strings FileHoundTests/App/MainMenuBuilderTests.swift FileHoundUITests/UpdatePreferencesSmokeTests.swift
git commit -m "更新：接入主菜单与偏好设置检查入口"
```

### Task 3: Split build outputs and feed metadata by architecture

**Files:**
- Modify: `Scripts/build_dmg.sh`
- Modify: `Scripts/generate_appcast.sh`

- [ ] **Step 1: Prove the current scripts are still universal-only**

Run:

```bash
bash Scripts/build_dmg.sh --help | rg -- '--arch'
bash Scripts/generate_appcast.sh --help | rg 'arm64|x86_64'
```

Expected: FAIL because neither script documents architecture-specific behavior yet.

- [ ] **Step 2: Add explicit architecture selection to the DMG builder**

Update `Scripts/build_dmg.sh` so it accepts and validates one architecture:

```bash
ARCH=""
case "$1" in
  --arch)
    ARCH="$2"
    ;;
esac

[[ "$ARCH" == "arm64" || "$ARCH" == "x86_64" ]] || fail "--arch 必须是 arm64 或 x86_64"

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  ARCHS="$ARCH" \
  ONLY_ACTIVE_ARCH=YES \
  clean archive
```

and emit names like:

```bash
expected_path="$DMG_OUTPUT_DIR/FileHound_v${VERSION}_${BUILD_NUMBER}_${ARCH}.dmg"
```

- [ ] **Step 3: Generate architecture-specific feed files without dropping Sparkle signatures**

Update `Scripts/generate_appcast.sh` so it targets one architecture at a time:

```bash
ARCH=""
OUTPUT_PATH="$ROOT_DIR/appcast-${ARCH}.xml"
ARCHIVES_DIR="$ROOT_DIR/build/appcast-archives/${ARCH}"
```

and preserve enclosure attributes in the Python rewrite step:

```python
for name, value in source_enclosure.attrib.items():
    rewritten_enclosure.set(name, value)
rewritten_enclosure.set("url", github_asset_url)
```

- [ ] **Step 4: Inject architecture-specific Sparkle metadata during archive**

Update `Scripts/build_dmg.sh` so the archive command writes the release feed URL and public key explicitly:

```bash
SPARKLE_PUBLIC_KEY="EMkumAR7FRbjJ6T5LhBcK7yIcGnJAuAjU5RZFEm12JE="
SPARKLE_FEED_URL="https://raw.githubusercontent.com/wangwanjie/FileHound/main/appcast-${ARCH}.xml"

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS="$ARCH" \
  ONLY_ACTIVE_ARCH=YES \
  INFOPLIST_KEY_SUFeedURL="$SPARKLE_FEED_URL" \
  INFOPLIST_KEY_SUPublicEDKey="$SPARKLE_PUBLIC_KEY" \
  clean archive
```

Expected: PASS, with the generated archive bundle carrying the architecture-specific `SUFeedURL` and the existing Sparkle public key.

- [ ] **Step 5: Re-run script interface checks**

Run:

```bash
bash Scripts/build_dmg.sh --help
bash Scripts/generate_appcast.sh --help
```

Expected: PASS, documenting `--arch`, the architecture-specific output names, and the per-architecture appcast workflow.

- [ ] **Step 6: Commit the build and feed split**

```bash
git add Scripts/build_dmg.sh Scripts/generate_appcast.sh
git commit -m "发布：拆分双架构打包与更新源"
```

### Task 4: Publish both architecture assets in one release

**Files:**
- Modify: `Scripts/publish_github_release.sh`
- Modify: `README.md`

- [ ] **Step 1: Add a failing publication-interface check**

Run: `bash Scripts/publish_github_release.sh --help | rg 'multiple|arm64|x86_64'`

Expected: FAIL because the current publisher only documents a single DMG input.

- [ ] **Step 2: Teach the publisher to accept multiple DMGs**

Update the argument parser to collect more than one asset:

```bash
DMG_PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      DMG_PATHS+=("$(resolve_path "$2")")
      shift 2
      ;;
  esac
done

for dmg_path in "${DMG_PATHS[@]}"; do
  gh release upload "$TAG" "$dmg_path" --repo "$REPO" --clobber
done
```

- [ ] **Step 3: Document the new release sequence**

Update `README.md` to show a supported flow like:

```bash
./Scripts/build_dmg.sh --arch arm64
./Scripts/build_dmg.sh --arch x86_64
./Scripts/publish_github_release.sh \
  --dmg build/dmg/FileHound_v1.1.1_3_arm64.dmg \
  --dmg build/dmg/FileHound_v1.1.1_3_x86_64.dmg
./Scripts/generate_appcast.sh --arch arm64 --archive build/dmg/FileHound_v1.1.1_3_arm64.dmg
./Scripts/generate_appcast.sh --arch x86_64 --archive build/dmg/FileHound_v1.1.1_3_x86_64.dmg
```

and mention that users stuck on the broken `1.0` feed path may need a one-time manual upgrade.

- [ ] **Step 4: Re-run the publisher help check**

Run: `bash Scripts/publish_github_release.sh --help`

Expected: PASS, documenting repeated `--dmg` usage and the architecture-aware release flow.

- [ ] **Step 5: Commit the release-publication update**

```bash
git add Scripts/publish_github_release.sh README.md
git commit -m "发布：支持双架构 Release 资产上传"
```

### Task 5: Verify the repaired update path and close the OpenSpec checklist

**Files:**
- Modify: `openspec/changes/fix-update-pipeline-and-split-arch-releases/tasks.md`

- [ ] **Step 1: Run application-level tests**

Run:

```bash
xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/UpdateManagerTests -only-testing:FileHoundTests/MainMenuBuilderTests -only-testing:FileHoundUITests/UpdatePreferencesSmokeTests
```

Expected: PASS, covering shared update runtime behavior, the app-menu entry, and the Updates preferences smoke path.

- [ ] **Step 2: Build both architectures and inspect bundle metadata**

Run:

```bash
bash Scripts/build_dmg.sh --arch arm64 --no-notarize
bash Scripts/build_dmg.sh --arch x86_64 --no-notarize
plutil -p build/FileHound-arm64.xcarchive/Products/Applications/FileHound.app/Contents/Info.plist | rg 'SUFeedURL|SUPublicEDKey'
plutil -p build/FileHound-x86_64.xcarchive/Products/Applications/FileHound.app/Contents/Info.plist | rg 'SUFeedURL|SUPublicEDKey'
```

Expected:
- both builds succeed
- each bundle shows the architecture-specific `SUFeedURL`
- both bundles expose `SUPublicEDKey`

- [ ] **Step 3: Generate both appcasts and verify signature preservation**

Run:

```bash
arm64_dmg="$(ls -t build/dmg/FileHound_v*_arm64.dmg | head -1)"
x86_64_dmg="$(ls -t build/dmg/FileHound_v*_x86_64.dmg | head -1)"
bash Scripts/generate_appcast.sh --arch arm64 --archive "$arm64_dmg" --repo wangwanjie/FileHound
bash Scripts/generate_appcast.sh --arch x86_64 --archive "$x86_64_dmg" --repo wangwanjie/FileHound
rg -n 'sparkle:edSignature' appcast-arm64.xml appcast-x86_64.xml
```

Expected: PASS, with both generated feeds retaining Sparkle signature attributes.

- [ ] **Step 4: Mark the OpenSpec checklist complete**

Update `openspec/changes/fix-update-pipeline-and-split-arch-releases/tasks.md` so every completed item is checked off:

```markdown
- [x] 1.1 扩展 `UpdateManager`，统一暴露手动检查更新、启动时检查更新和运行时可用状态
```

- [ ] **Step 5: Commit verification and bookkeeping**

```bash
git add openspec/changes/fix-update-pipeline-and-split-arch-releases/tasks.md
git commit -m "验证：完成更新链路修复与双架构发布核对"
```
