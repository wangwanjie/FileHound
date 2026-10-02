# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概览

FileHound 是 Swift 5.10 + AppKit（纯代码 UI，无 Storyboard，布局用 SnapKit）实现的 macOS 文件搜索工具，对标 Find Any File。最低系统 macOS 12.0。依赖：SPM 引入 SnapKit / MMKV / Sparkle，CocoaPods 仅引入 Debug 用的 `ViewScopeServer`。

## 工程生成与构建

`project.yml`（XcodeGen）是工程配置的唯一来源，`FileHound.xcodeproj/project.pbxproj` 由它生成并入库。修改 target、依赖、Build Settings、版本号（`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`）时改 `project.yml`，再重新生成。

```bash
xcodegen generate          # postGenCommand 会自动执行 pod install
xcodebuild -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' build
xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests
xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundUITests
# 单个测试类 / 方法
xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchExecutorTests/testXxx
```

始终使用 `FileHound.xcworkspace` + `FileHound` scheme。`FileHoundHelper` 是命令行 tool target，选它运行不会出现主窗口。

## 架构

### 启动与窗口

`App/ApplicationMain.swift` 手动创建 `NSApplication` 和 `AppDelegate`。`AppDelegate` 负责初始化 MMKV、构建主菜单（`MainMenuBuilder`）、注册全局快捷键（`LaunchShortcutController`）、配置 `UpdateManager`，然后打开 `SearchWindowController`。

### 搜索链路（实际运行路径）

`SearchFormViewController` / `SearchRulesViewController` 收集规则 → `SearchRequest`（`rootPath` + `[SearchRuleSelection]`）→ `SearchWorkflowController.start` 在后台 `Task` 中调用 `SearchExecutor.executeStreaming` → 通过 `onStateChange` / `onResults` 回到主线程驱动 UI 与 `SearchResultsWindowController`。

- 规则模型 `SearchRuleField` / `SearchRuleSelection` 定义在 `Modules/SearchRules/SearchRuleCatalog.swift`，新增搜索条件从这里开始，再在 `SearchExecutor` 的匹配逻辑和 `SpotlightSearchService.buildPredicate` 中补实现。
- `SearchExecutor` 先尝试 Spotlight（`SpotlightSearchService`，受 `includeSpotlightResults` 偏好控制），文本内容搜索若 Spotlight 已有结果则直接返回；否则用 `DirectoryWalker` 遍历，结合 `SpecialFolderPlanner`（偏好中的特殊文件夹包含/排除/慢速路径）、`ContentMatcher`、`MetadataEvaluator` 过滤，按路径去重。
- `FilesystemAccessProviding` 抽象了文件访问，`LocalFilesystemProvider` 为默认实现；`PrivilegedFilesystemProvider` 与 `FileHoundHelper` 目前只是骨架。
- `SearchEngine/Query`（`SearchQuery` / `QueryRule` / `QueryCompiler`）和 `SearchPlanBuilder` 只被单元测试引用，未接入运行路径。

### 持久化与设置

- `AppSettings`（`Common/Storage`）基于 `KeyValueStoring` 协议，生产用 `MMKVKeyValueStore`，测试用 `InMemoryKeyValueStore`。偏好以 `*.v1` 键存为 Codable 结构（`GeneralSearchPreferences`、`SearchExecutionPreferences` 等，见 `SearchParityModels.swift`）。
- `SavedSearchStore`、`SearchHistoryStore`、`RecentLocationStore`、`SearchSessionStore`、`SpecialFoldersStore` 管理已保存搜索、历史、最近位置、会话恢复与特殊文件夹配置。

### 本地化与主题

- 所有 UI 文案走 `L10n.string(key)` / `L10n.format(key, ...)`，支持应用内热切换语言（`LocalizationController` 通过 Combine publisher 广播）。新增 key 需同时补齐 `Resources/Localization/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings`，三份文件行数保持一致。
- 主题由 `ThemeController` 管理，同样通过 publisher 通知各视图刷新。

### 更新

`UpdateManager` 封装 Sparkle（编译条件 `SPARKLE_ENABLED`，通过 `SparkleUpdateDriving` 协议注入以便测试）。feed 按架构区分：`appcast-arm64.xml` / `appcast-x86_64.xml`，由 `build_dmg.sh` 在打包时写入对应架构的 `SUFeedURL`。

## 测试约定

- 单元测试用 `FileHoundTests/Support/TemporaryFixtureTree.swift` 构造临时目录树。
- UI 测试通过启动参数控制 App 行为：`--uitesting` 重置语言/主题/更新策略；`--fixture-results*`、`--fixture-streaming-search*`、`--fixture-delayed-search` 注入假搜索结果；`--open-*-preferences-on-launch` 直接打开偏好设置指定页；`--enable-*/--disable-*` 切换搜索偏好。这些分支散布在 `AppDelegate` 和 `SearchWorkflowController` 中，新增 UI 测试场景时沿用此模式。启动前调用 `AppLaunchHelper.prepareForLaunch` 结束残留实例。

## 发布

```bash
./Scripts/build_dmg.sh --arch arm64            # 归档 Release、签名、notarize + staple；本地测试加 --no-notarize
./Scripts/build_dmg.sh --arch x86_64
./Scripts/publish_github_release.sh --dmg build/dmg/<arm64>.dmg --dmg build/dmg/<x86_64>.dmg
./Scripts/generate_appcast.sh --arch arm64 --archive build/dmg/<arm64>.dmg
./Scripts/generate_appcast.sh --arch x86_64 --archive build/dmg/<x86_64>.dmg
```

`--arch` 必填。生成的 `appcast-<arch>.xml` 需提交并推送到 `main`（Sparkle 从 raw.githubusercontent 读取）。前置条件：`gh auth login`、notarytool profile `vanjay_mac_stapler`、Keychain 中的 Sparkle 私钥（account `cn.vanjay.FileHound.sparkle`）。

## 开发流程

- 较大功能先用 OpenSpec 建变更：`openspec/changes/<name>/`（proposal / design / specs / tasks），完成后归档到 `openspec/changes/archive/` 并同步 `openspec/specs/`。相关 skill 在 `.codex/skills/openspec-*`。设计与实施计划另存于 `docs/superpowers/{specs,plans}/`。
- 提交信息使用中文，常见前缀：`修复：`、`更新：`、`发布：`、`文档：`、`feat：`、`chore:`。
