## Why

FileHound 当前的 Sparkle 更新链路并不可靠：发布包中缺少稳定的 feed 元数据，`appcast` 后处理会破坏签名相关字段，更新设置页里的“立即检查更新”按钮也可能直接不可用。与此同时，正式发布仍然使用单一 Universal 包，不满足 `arm64` 与 `x86_64` 分开打包、分开分发和分开更新的要求。

## What Changes

- 修复发布包的 Sparkle 元数据注入，确保分发产物稳定包含有效的 `SUFeedURL` 与 `SUPublicEDKey`。
- 修复 `appcast` 生成流程，保留 Sparkle `enclosure` 的签名字段，并把按版本发布的资产链接安全回填到 feed。
- 将正式发布流程调整为按 `arm64` 与 `x86_64` 分架构构建 DMG、分架构生成 `appcast`、分架构写入 feed URL。
- 为应用增加统一的更新入口，在设置页和主菜单都可以触发检查更新，并让启动时检查更新真正与 Sparkle 运行时配置联动。
- 调整更新设置页的交互，使“立即检查更新”按钮和不可用提示反映真实的更新能力状态。

## Capabilities

### New Capabilities
- `app-update-integration`: 定义 FileHound 应用内手动检查更新、启动时检查更新和菜单级更新入口的行为。

### Modified Capabilities
- `release-distribution-pipeline`: 将发布链路扩展为分架构构建、分架构 feed、签名保留和可消费的 Sparkle 产物。
- `search-preferences-parity`: 调整更新偏好设置页中“立即检查更新”按钮的启用逻辑、提示文案和与运行时更新能力的联动。

## Impact

- 受影响代码包括 [UpdateManager.swift](/Users/VanJay/Documents/Work/Private/FileHound/FileHound/Common/Services/UpdateManager.swift)、[UpdatePreferencesViewController.swift](/Users/VanJay/Documents/Work/Private/FileHound/FileHound/Modules/Preferences/UpdatePreferencesViewController.swift)、[AppDelegate.swift](/Users/VanJay/Documents/Work/Private/FileHound/FileHound/App/AppDelegate.swift) 和 [MainMenuBuilder.swift](/Users/VanJay/Documents/Work/Private/FileHound/FileHound/App/MainMenuBuilder.swift)。
- 受影响脚本包括 [build_dmg.sh](/Users/VanJay/Documents/Work/Private/FileHound/Scripts/build_dmg.sh)、[generate_appcast.sh](/Users/VanJay/Documents/Work/Private/FileHound/Scripts/generate_appcast.sh) 和 [publish_github_release.sh](/Users/VanJay/Documents/Work/Private/FileHound/Scripts/publish_github_release.sh)。
- 受影响规范包括 [release-distribution-pipeline/spec.md](/Users/VanJay/Documents/Work/Private/FileHound/openspec/specs/release-distribution-pipeline/spec.md) 与 [search-preferences-parity/spec.md](/Users/VanJay/Documents/Work/Private/FileHound/openspec/specs/search-preferences-parity/spec.md)，并将新增 `app-update-integration` 规范。
