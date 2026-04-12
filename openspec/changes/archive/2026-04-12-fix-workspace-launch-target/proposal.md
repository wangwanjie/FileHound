## Why

引入 CocoaPods 后，开发入口从 `FileHound.xcodeproj` 变成了 `FileHound.xcworkspace`。当前 workspace 下最近被 Xcode 记住并运行的是 `FileHoundHelper` 这个命令行工具 target，而不是 `FileHound.app`，所以会出现“能编译通过，但看不到 App 拉起”的现象。

这个问题需要现在处理，因为它直接破坏了最基本的本地开发反馈链路，并且会让后续所有 UI 调试都建立在错误的运行目标上。

## What Changes

- 为 workspace 开发入口定义稳定的主运行目标，保证从 `FileHound.xcworkspace` 点击 Run 时默认启动 `FileHound.app`。
- 为主 App 显式生成并提交可复用的 scheme/launch 配置，减少 Xcode 本地用户状态对运行行为的影响。
- 明确 `FileHoundHelper` 作为辅助 tool target 的角色，避免它在常规开发流程中被误当成 UI 启动入口。
- 补充验证步骤，确保 CocoaPods 集成后依旧可以从 workspace 构建并拉起主窗口。

## Capabilities

### New Capabilities
- `workspace-launch-target`: 约束 Xcode workspace 开发流程必须以 `FileHound.app` 作为默认可运行产物，并防止 helper/tool target 抢占常规 Run 入口。

### Modified Capabilities

无

## Impact

- 受影响代码和配置：`project.yml`、生成出的 Xcode scheme/项目元数据、可能的开发文档。
- 受影响系统：Xcode workspace 启动流程、CocoaPods 集成后的本地开发体验。
- 受影响目标：`FileHound`、`FileHoundHelper`、`Pods` workspace 集成。
