# FileHound

一个使用 Swift + AppKit 开发的 macOS 文件搜索工具，目标体验接近 Find Any File。

## 当前能力

- 代码化主窗口与自定义菜单
- 查询模型与执行计划
- 目录遍历与文本内容匹配骨架
- 列表/树形结果浏览与预览面板
- 已保存搜索与偏好设置窗口
- 主题切换与语言热切换
- 权限诊断与特权 Helper 骨架
- Sparkle 更新入口与 DMG / appcast 脚本

## 本地开发

```bash
xcodegen generate
open FileHound.xcworkspace
xcodebuild -workspace FileHound.xcworkspace -scheme FileHound build -destination 'platform=macOS'
xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests
xcodebuild test -workspace FileHound.xcworkspace -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundUITests
```

`xcodegen generate` 会自动执行 `pod install`，然后再从 `FileHound.xcworkspace` 进入开发。

日常 UI 调试请始终从 `FileHound.xcworkspace` 的 `FileHound` scheme 启动。

如果引入 CocoaPods 后出现“能编译但看不到 App 窗口”，先检查 Xcode 顶部选中的 scheme 是否误切到了 `FileHoundHelper`。这个 target 是辅助 tool，不会拉起主界面。

如果 Xcode 仍然记住了错误的运行目标，可以在关闭 Xcode 后删除本地用户态状态文件，再重新打开 workspace：

```bash
rm -f FileHound.xcodeproj/project.xcworkspace/xcuserdata/"$USER".xcuserdatad/UserInterfaceState.xcuserstate
```

## 打包

```bash
./Scripts/build_dmg.sh --arch arm64
./Scripts/build_dmg.sh --arch x86_64
./Scripts/publish_github_release.sh \
  --dmg build/dmg/FileHound_v1.1.0_2_arm64.dmg \
  --dmg build/dmg/FileHound_v1.1.0_2_x86_64.dmg
./Scripts/generate_appcast.sh --arch arm64 --archive build/dmg/FileHound_v1.1.0_2_arm64.dmg
./Scripts/generate_appcast.sh --arch x86_64 --archive build/dmg/FileHound_v1.1.0_2_x86_64.dmg
```

说明：

- `./Scripts/build_dmg.sh` 必须显式传入 `--arch arm64` 或 `--arch x86_64`，默认从 `FileHound.xcworkspace` 归档对应架构的 `Release`，并执行 notarize + staple
- 如需仅本地测试 DMG，可使用 `./Scripts/build_dmg.sh --arch <arch> --no-notarize`
- `./Scripts/publish_github_release.sh` 支持重复传入 `--dmg`，将同一版本的多架构 DMG 一次上传到 GitHub Release `v<版本号>`
- `./Scripts/generate_appcast.sh` 必须显式传入 `--arch`，会把对应架构的 DMG 归档到 `build/appcast-archives/<arch>/`，并生成仓库根目录的 `appcast-<arch>.xml`
- 发布后仍需把更新后的 `appcast-arm64.xml` 和 `appcast-x86_64.xml` 提交并推送到默认分支
- 已安装旧 `1.0` 且缺失有效 Sparkle 元数据的机器，可能仍需要先手动升级一次，之后才会进入新的自动更新链路

发布前置条件：

- 已执行 `gh auth login`
- 本机存在 `vanjay_mac_stapler` notarytool profile
- 已生成 Sparkle 私钥：

```bash
<Sparkle bin>/generate_keys --account cn.vanjay.FileHound.sparkle
```

当前 Sparkle feed 地址为：

```text
arm64:   https://raw.githubusercontent.com/wangwanjie/FileHound/main/appcast-arm64.xml
x86_64:  https://raw.githubusercontent.com/wangwanjie/FileHound/main/appcast-x86_64.xml
```
