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
xcodebuild test -project FileHound.xcodeproj -scheme FileHoundTests -destination 'platform=macOS'
xcodebuild test -project FileHound.xcodeproj -scheme FileHoundUITests -destination 'platform=macOS'
```

## 打包

```bash
./Scripts/build_dmg.sh
./Scripts/generate_appcast.sh
```
