## Context

当前仓库在引入 CocoaPods 后同时存在 `FileHound.xcodeproj` 与 `FileHound.xcworkspace`。主产品 `FileHound` 是 macOS App，`FileHoundHelper` 是 `com.apple.product-type.tool` 的辅助命令行 target。

现有证据表明问题不在 App 代码入口：

- `FileHound/App/ApplicationMain.swift` 仍然定义了有效的 `@main` 入口。
- `xcodebuild -workspace FileHound.xcworkspace -scheme FileHound build` 能成功生成 `FileHound.app`。
- 最近的 Xcode Launch 记录是 `Run FileHoundHelper`，而不是 `Run FileHound`。
- Xcode 用户界面状态中存在 `FileHoundHelper` 的最近运行 scheme 记录。

因此根因是 workspace 开发入口漂移到了 helper/tool target，而不是 CocoaPods 让主 App 无法构建或无法显示窗口。

## Goals / Non-Goals

**Goals:**

- 让从 `FileHound.xcworkspace` 进入开发时，有稳定、明确、可复现的主运行目标。
- 降低 Xcode 本地用户态 scheme 记忆对团队开发体验的影响。
- 保留 `FileHoundHelper` 的辅助职责，但避免它抢占日常 UI 调试入口。
- 让修复可以纳入工程生成流程，而不是停留在某台机器的临时状态修补。

**Non-Goals:**

- 不改变 `FileHoundHelper` 的业务实现或运行机制。
- 不调整 CocoaPods 依赖本身的功能接入方式。
- 不在本次变更中重构主 App 窗口逻辑、AppDelegate 或搜索流程。

## Decisions

### 1. 将问题定义为“运行入口配置缺失”，而不是“启动时崩溃”

`FileHound.app` 已经可以成功构建，且仓库中没有新的 `FileHound` 启动崩溃记录。最近的实际运行记录明确指向 `FileHoundHelper`。因此修复重点必须放在 scheme/launch 配置，而不是继续排查 App 启动代码。

备选方案：

- 继续检查 App 启动逻辑或窗口显示链路。
  - 放弃原因：现有证据已经说明 Xcode 最近根本没有运行主 App，这条路径无法解释“完全没有窗口”。

### 2. 通过工程生成配置显式产出主 App 的共享 scheme

项目使用 `project.yml` 生成工程。运行入口的稳定性应当由可提交、可复现的工程描述控制，而不是依赖 `xcuserdata` 中的本地状态。实现上应优先在工程生成配置里显式声明 `FileHound` 的共享 scheme，并在重新生成后将产物纳入版本管理。

备选方案：

- 只在本机 Xcode 里手动切回 `FileHound` scheme。
  - 放弃原因：只能修复当前机器当前用户，重新生成工程、切换 workspace 或换机器后问题会再次出现。
- 直接提交 `xcuserdata`。
  - 放弃原因：这是用户私有状态，易抖动、不可维护，也不适合作为团队配置来源。

### 3. 保留 helper target，但将其从常规 UI 运行路径中降级

`FileHoundHelper` 仍然需要保留为独立目标；但需要避免它成为 workspace 中最容易被误运行的入口。实现上可以通过显式主 scheme、必要时约束 helper scheme 生成方式、以及补充开发文档来降低误用。

备选方案：

- 删除 helper target 的可运行能力。
  - 放弃原因：辅助工具目标仍可能需要独立构建或调试，完全移除 runnable 属性风险过高。

### 4. 将验证分成 CLI 与 Xcode 两层

CLI 验证负责确认 workspace 下 `FileHound` scheme 可以稳定构建，Xcode 验证负责确认从 IDE 点击 Run 时实际拉起的是 `FileHound.app` 并出现主窗口。两层都需要，避免只验证“能 build”却遗漏“run 入口仍然错误”。

## Risks / Trade-offs

- [XcodeGen 生成能力与当前工程状态不一致] → 先在设计中要求以生成配置为单一事实来源，实施时验证生成产物是否真的包含共享 scheme。
- [CocoaPods 仍会生成多个 Pods 相关 schemes，增加误选概率] → 通过显式主 App scheme 和文档化运行入口降低风险，而不是尝试控制所有 Pods 自动 scheme。
- [历史本地状态仍可能保留错误的最近运行记录] → 修复后补充一次清理/重新选择主 scheme 的验证步骤，确认新配置已生效。
- [Helper target 未来确实需要单独调试] → 保留 helper target，只约束默认开发入口，不阻断专门调试场景。

## Migration Plan

1. 在工程生成配置中显式声明主 App 的共享 scheme 与运行目标。
2. 重新生成 Xcode 工程并确认相关 scheme 元数据进入版本管理。
3. 使用 workspace 重新验证 `FileHound` 的 build/run 路径。
4. 若本地仍沿用旧的错误运行记录，手动切回 `FileHound` 一次并确认后续保持稳定。

回滚策略：

- 回退工程生成配置与 scheme 产物改动，恢复到当前自动生成行为。

## Open Questions

- 当前使用的 XcodeGen 版本是否支持直接抑制 `FileHoundHelper` 的自动 scheme 暴露；若不支持，则只保证主 App scheme 明确存在并被文档化。
- 是否需要在 README 或开发文档中明确要求“CocoaPods 集成后统一从 `FileHound.xcworkspace` 的 `FileHound` scheme 启动”。
