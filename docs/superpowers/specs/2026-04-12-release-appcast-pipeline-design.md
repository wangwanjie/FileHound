# FileHound 打包与 Appcast 发布流程设计

日期：2026-04-12  
状态：已确认，待实现

## 1. 背景

FileHound 当前已经具备：

- Sparkle 运行时代码入口
- `scripts/build_dmg.sh`
- `scripts/generate_appcast.sh`
- GitHub `origin`
- `MARKETING_VERSION = 1.0.0`

但现状仍停留在骨架阶段：

- `build_dmg.sh` 仍使用 `.xcodeproj` 而不是 `.xcworkspace`
- DMG 脚本没有正式发布级别的公证与 staple 默认链路
- `generate_appcast.sh` 仍输出 `example.com` 占位地址
- 仓库内还没有完善的 GitHub Release 发布脚本
- Sparkle 需要的 `SUFeedURL` / `SUPublicEDKey` 还没有形成完整的分发闭环

用户已经明确要求：

- 采用“分步脚本”的发布方式，人工可以顺序调用
- 默认产出的应当是正式发布链路，必须公证并 staple
- 参考 `/Users/VanJay/Documents/Work/Private/HostsEditor`
- DMG 生成部分优先使用全局可用的 `create_pretty_dmg.sh`
- 先发布 `1.0` 版本

## 2. 目标

- 建立可重复执行的三段式发布链路：
  1. 构建并生成正式可分发 DMG
  2. 发布 GitHub Release
  3. 生成并更新 Sparkle `appcast.xml`
- 默认以 `.xcworkspace` 为入口，兼容当前 CocoaPods 场景
- 让正式分发产物包含 Sparkle 所需的 feed metadata
- 让第一版正式发布基线对齐当前 `1.0.0` 工程版本

## 3. 非目标

- 不在本 change 内引入 GitHub Actions 自动发布
- 不切换到 GitHub Pages 或外部 CDN 托管 appcast
- 不在本 change 内设计 DMG 背景艺术稿
- 不扩展为“一键全自动总脚本”，仍保持分步、人工可插入

## 4. 发布流程方案

### 4.1 采用三段式脚本

发布流程拆成三个脚本：

1. `scripts/build_dmg.sh`
   - 使用 `FileHound.xcworkspace`
   - 构建 Release
   - 对 `.app` 做发布级签名校验 / 公证 / staple
   - 使用 `create_pretty_dmg.sh` 输出版本化 DMG

2. `scripts/publish_github_release.sh`
   - 读取 DMG、版本号、tag、release title
   - 发布或更新 GitHub Release
   - 上传 DMG 资产

3. `scripts/generate_appcast.sh`
   - 基于本地 DMG 归档目录生成 `appcast.xml`
   - 下载地址改写为 GitHub Release 资产地址
   - 输出到仓库根目录，供 Sparkle 使用

这是当前最符合要求的方式：脚本有清晰边界，人工可以插入检查，也方便将来单独重跑某一步。

### 4.2 Appcast 托管方式

`appcast.xml` 直接放在仓库根目录，并提交到 Git：

- 发布后由 GitHub 原始文件地址提供 Sparkle feed
- `SUFeedURL` 指向仓库中稳定的 `appcast.xml`

这样不引入 GitHub Pages 或独立静态托管，复杂度最低，也符合当前仓库形态。

### 4.3 初始正式版本

本 change 以当前工程中的：

- `MARKETING_VERSION = 1.0.0`
- `CURRENT_PROJECT_VERSION = 1`

作为第一版正式发布基线。

tag 命名采用 `v1.0.0`，DMG 产物命名采用带版本号的稳定格式，避免后续 appcast 和 GitHub Release 资产名漂移。

## 5. 关键决策

### 5.1 `build_dmg.sh` 默认走正式发布链路

`build_dmg.sh` 默认必须：

- 使用发布配置构建
- 进行 notarize
- 对最终 `.app` / `.dmg` 执行 staple

只有显式参数才允许跳过公证。

原因：

- 用户已经明确要求默认正式发布链路必须公证并 staple
- 这能避免误把测试包当正式包上传

备选方案：

- 默认只产出本地 DMG，公证作为可选
- 不采用，因为与当前确认的发布要求冲突

### 5.2 继续使用 `create_pretty_dmg.sh`

DMG 生成不复刻 `HostsEditor` 的自定义绘图背景方案，而是优先调用全局命令：

- `create_pretty_dmg.sh --app-path ... --dmg-name ... --append-version --output-dir ...`

原因：

- 用户已明确要求可直接使用该命令
- 当前任务重点是发布闭环，不是自定义 DMG 美术

### 5.3 让 GitHub Release 成为 appcast 下载源

`generate_appcast.sh` 生成 appcast 时，下载链接统一指向 GitHub Releases 资产地址，而不是本地占位地址或其他站点。

原因：

- 现有 `origin` 已经指向 GitHub
- GitHub Release 资产天然适合作为 Sparkle 下载源
- 与 `HostsEditor` 参考实现一致

### 5.4 把 Sparkle feed metadata 纳入正式分发配置

本 change 需要把：

- `SUFeedURL`
- `SUPublicEDKey`

纳入正式可分发构建所需的配置来源，保证 `UpdateManager` 在发布包中可用。

原因：

- 当前运行时代码已经依赖这两个 key 判断是否能检查更新
- 只有脚本没有 feed metadata，更新功能仍然不会真正工作

## 6. 脚本职责边界

### 6.1 `build_dmg.sh`

负责：

- 读取工程版本号
- 使用 `FileHound.xcworkspace` 构建 Release
- 校验签名信息
- 默认使用 `vanjay_mac_stapler` 执行 notarize
- staple 发布产物
- 输出版本化 DMG 到 `build/dmg/`

不负责：

- 发布 GitHub Release
- 生成 appcast

### 6.2 `publish_github_release.sh`

负责：

- 推断或显式读取 `OWNER/REPO`
- 创建 / 更新 `v1.0.0` 风格的 Release
- 上传指定 DMG
- 写入 release notes 或启用 GitHub 自动 notes

不负责：

- 本地构建
- appcast XML 生成

### 6.3 `generate_appcast.sh`

负责：

- 维护本地 `build/appcast-archives/`
- 从归档 DMG 生成 Sparkle appcast
- 用 GitHub Release 资产 URL 回填 enclosure
- 生成仓库根目录的 `appcast.xml`

不负责：

- 构建 app
- 上传 GitHub Release

## 7. 验证策略

### 7.1 脚本级验证

- `build_dmg.sh --help`
- `generate_appcast.sh --help`
- `publish_github_release.sh --help`

### 7.2 产物验证

- 生成的 DMG 命名符合版本策略
- `spctl` / `codesign` 可验证签名与 staple 状态
- `appcast.xml` 中 enclosure URL 指向正确的 GitHub Release 资产
- `SUFeedURL` 与 `SUPublicEDKey` 已进入分发构建配置

### 7.3 发布验证

- `v1.0.0` Release 可创建并包含 DMG 资产
- `appcast.xml` 可被 Sparkle 消费
- 发布说明与版本号一致

## 8. 风险与缓解

- 公证流程依赖本地凭证与网络
  - 缓解：默认使用 `vanjay_mac_stapler`，并提供显式报错与跳过参数
- GitHub Release 与 appcast 可能短时间不同步
  - 缓解：明确推荐发布顺序为 build -> release -> appcast -> commit appcast
- `SUFeedURL` 若指向不稳定地址会导致更新失效
  - 缓解：固定使用 GitHub 仓库的稳定 appcast 地址
- 当前 README 中脚本路径大小写不一致
  - 缓解：实现时同步修正文档与示例命令

## 9. 完成标准

- 三个脚本职责清晰，且都可单独人工调用
- `build_dmg.sh` 默认走正式发布链路，包含 notarize 与 staple
- `publish_github_release.sh` 能将版本化 DMG 发布到 GitHub Release
- `generate_appcast.sh` 生成可用的仓库根目录 `appcast.xml`
- 分发构建具备 Sparkle 所需 feed metadata
- 能以当前 `1.0.0` 工程版本完成第一次正式发布
