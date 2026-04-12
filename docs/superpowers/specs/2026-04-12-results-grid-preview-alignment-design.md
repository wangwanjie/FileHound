# FileHound Grid 结果项 Preview Size 对齐修复设计

日期：2026-04-12  
状态：已确认，待实现

## 1. 背景

当前结果窗口的 grid 视图已经支持 `previewSize` 滑杆，但在切换预览尺寸时，结果项名称与图标会出现“看起来没有水平居中对齐”的问题。这个问题只出现在 grid 视图，table / tree 视图已有单独的文本垂直居中策略与测试覆盖。

代码现状是：

- `SearchResultsViewController` 只把 `previewSize` 应用到 `ResultsCollectionViewController`
- grid item 的 `iconView` 明确做了 `centerX == superview`
- grid item 的 `titleLabel` 占满单元格底部宽度，并通过 `attributedStringValue` 展示高亮文本
- `SearchResultNameHighlighter` 生成的富文本没有显式段落对齐信息

在 AppKit 下，一旦 `NSTextField` 使用 `attributedStringValue`，单纯设置控件的 `alignment = .center` 并不总能稳定约束最终绘制效果。随着 preview 尺寸变化、文本换行与中间截断重新计算，标题会产生视觉中心偏移。

## 2. 目标

- 修复 grid 视图中，调整 `previewSize` 后图标与标题的水平居中对齐问题
- 保持现有的 `最多两行 + 中间截断` 行为
- 保持现有 preview size 的尺寸公式与 grid item 的整体排布不变
- 为该回归补充自动化测试，覆盖至少两个 preview size 档位

## 3. 非目标

- 不修改 table / tree 视图的文本布局
- 不重做 grid item 的视觉样式、间距或缩略图策略
- 不调整 preview slider 的取值范围与交互
- 不引入截图对比或新的 UI 测试框架

## 4. 问题定位

### 4.1 受影响范围

问题只影响 `ResultsCollectionViewController` 中的 `ResultGridItem`。`previewSize` 的变化会触发：

1. 更新 flow layout 的 item size
2. 更新 grid item 的图标尺寸约束
3. 重新设置标题富文本

图标始终以 cell 的水平中心为基准，但标题富文本没有明确的段落居中信息，因此会依赖默认段落样式与换行结果。

### 4.2 为什么不能全局改高亮器

`SearchResultNameHighlighter` 同时被 table、tree、grid 三种结果视图复用。若直接把默认输出改成 `.center`，会把表格和树视图的名称列也一起改成居中，破坏现有 Finder / FAF 风格的左对齐表现，而且仓库里已经有 table / tree 的对齐回归测试。

因此，这次修复必须是 grid-only。

## 5. 方案

### 5.1 在 grid 渲染路径中补齐居中段落样式

推荐方案是在 `ResultGridItem` 渲染标题时，对高亮器返回的富文本做一次 grid 专属后处理：

- 保留已有字体、前景色、高亮背景色范围
- 为整段文本补一个 `NSMutableParagraphStyle`
- 显式设置 `alignment = .center`
- 仅在 grid item 中使用，不改变 table / tree 的默认文本输出

这样可以用最小改动修正视觉中心，同时避免把共享高亮工具的默认行为扩散到其他视图。

### 5.2 保持现有布局与文本策略不变

本次不调整以下内容：

- `layout.itemSize = NSSize(width: iconSize + 60, height: iconSize + 44)`
- `titleLabel.maximumNumberOfLines = 2`
- `titleLabel.lineBreakMode = .byTruncatingMiddle`
- 缩略图异步加载策略

也就是说，这次修的是“标题实际渲染时的对齐信息”，不是重算 grid item 的版式。

### 5.3 为 grid 增加可测的对齐度量

现有测试已经为 table / tree 暴露了 `debugNameCellAlignmentOffset` 一类的几何度量。grid 视图可以沿用同样思路，在 `DEBUG` 下增加轻量级观测能力，例如：

- 基于一个测试用 `ResultGridItem` 计算图标中心与标题绘制区域中心的横向偏差
- 或暴露 grid item 内部标题富文本是否带有 `.center` 段落样式，并结合几何断言验证

测试重点不是逐像素截图，而是保证：

- preview size 变大时依然居中
- preview size 变小时依然居中
- 长文件名仍保持“两行以内 + 中间截断”

## 6. 备选方案与取舍

### 6.1 备选方案 A：全局修改 `SearchResultNameHighlighter`

优点：

- 代码改动表面上更集中

缺点：

- 会影响 table / tree 视图
- 与现有名称列左对齐预期冲突

结论：拒绝。

### 6.2 备选方案 B：只改 `titleLabel` 约束宽度

优点：

- 不改富文本构造逻辑

缺点：

- 不能解决 attributed string 缺少段落对齐信息的问题
- 只能缓解，不能从根因上保证不同 preview size 下的文本居中

结论：拒绝。

## 7. 测试策略

### 7.1 单元测试

- 扩展 `SearchResultsViewControllerTests`
- 补充 grid 模式下多档 `previewSize` 的对齐回归测试
- 复用现有 debug 风格，断言标题中心与图标中心的横向偏差小于阈值

### 7.2 回归边界

- 默认 preview size
- 放大后的 preview size
- 较小 preview size
- 长文件名与高亮命中场景

## 8. 风险与缓解

- 富文本段落样式可能覆盖未来更细粒度的段落属性
  - 缓解：仅对 grid 渲染路径整段补齐居中段落，不改共享默认输出
- 异步缩略图回填可能影响测试时机
  - 缓解：测试以初始布局和文本属性为主，不依赖异步缩略图完成
- 视觉中心问题可能与极端长文件名宽度有关
  - 缓解：本次先修正富文本对齐根因；若仍有边缘视觉问题，再单独开 change 评估 cell 宽度策略

## 9. 完成标准

- grid 模式下调整 `previewSize` 后，结果项标题与图标保持水平居中
- 现有 table / tree 对齐行为不变
- 标题继续保持“最多两行 + 中间截断”
- 自动化测试覆盖至少两个 preview size 档位并可稳定通过
