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
./Scripts/build_dmg.sh
./Scripts/generate_appcast.sh
```
