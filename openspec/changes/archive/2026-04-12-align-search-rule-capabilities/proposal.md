## Why

当前 FileHound 的搜索条件编辑器已经暴露出较多字段与操作符，但实际支持能力和界面可见项并不一致。日期条件仍停留在旧语义，`kind` 还只是简化文本匹配，`comments` 与 `script` 之类的字段则会让用户看到“能选但不能用”的假能力。

这个问题需要在 1.0 发布前收口，因为它直接影响主搜索窗口的可信度。用户必须能够清楚知道哪些条件可用、哪些暂不支持，以及当前规则是否可以真正发起搜索。

## What Changes

- 将日期字段改为 FAF 风格操作符，统一 `on or after`、`on or before`、`exactly`、`within the last`、`today`、`yesterday` 的交互与执行语义。
- 为 `kind` 字段增加 FAF 风格的 `is / is not + 类型下拉` 条件模型，并实现首版文件类型归一化匹配。
- 建立统一的搜索条件能力矩阵，作为字段、操作符、值编辑器、支持状态和阻塞提示的唯一数据源。
- 对当前全部可见条件做审计，将 `comments`、`script` 等暂不可交付能力保留在菜单中但置灰，并在内部载入或无效组合出现时阻止搜索并提示原因。
- 在主搜索窗口接入规则校验结果，使无效规则不会静默进入搜索执行流程。

## Capabilities

### New Capabilities

无

### Modified Capabilities

- `find-window-parity`: 搜索条件编辑器的可见能力、字段专用编辑器、规则校验和可执行性约束将更新为更接近 FAF 的行为。

## Impact

- 受影响代码：`FileHound/Modules/SearchRules/`、`FileHound/Modules/SearchWindow/SearchFormViewController.swift`、`FileHound/SearchEngine/Execution/SearchExecutor.swift`、相关本地化与测试文件。
- 受影响行为：日期条件菜单、`kind` 条件菜单、搜索按钮可用性、规则恢复时的阻塞提示、本地搜索执行逻辑。
- 受影响系统：主搜索窗口规则编辑体验、本地搜索执行链路、规则序列化与回显。
