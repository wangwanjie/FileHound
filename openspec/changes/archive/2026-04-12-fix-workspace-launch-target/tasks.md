## 1. 固化主运行入口

- [x] 1.1 检查 `project.yml` 与当前生成工程的 scheme 产物，确认 `FileHound` 主 App 的共享 scheme 是否缺失或未被显式声明
- [x] 1.2 在工程生成配置中显式定义 `FileHound` 的主运行 scheme，并确保其 runnable 指向 `FileHound.app`
- [x] 1.3 评估并收敛 `FileHoundHelper` 的 scheme 暴露方式，避免其成为常规 UI 调试的默认入口

## 2. 重新生成并验证工程

- [x] 2.1 重新生成 Xcode 工程，确认新的 scheme/项目元数据进入版本管理
- [x] 2.2 使用 `xcodebuild` 在 `FileHound.xcworkspace` 下验证 `FileHound` scheme 仍可成功构建
- [x] 2.3 在 Xcode 中从 workspace 运行主 scheme，确认实际拉起的是 `FileHound.app` 而不是 `FileHoundHelper`

## 3. 收尾与说明

- [x] 3.1 记录 CocoaPods 集成后的正确开发入口，明确应从 `FileHound.xcworkspace` 的 `FileHound` scheme 启动
- [x] 3.2 补充必要的本地清理/切换说明，帮助已有错误运行记录的开发环境恢复到正确主入口
