## 1. 建立统一能力矩阵

- [x] 1.1 在 `SearchRuleCatalog` 中引入字段能力矩阵，统一声明字段标题、值编辑器、操作符集合、支持状态与阻塞提示
- [x] 1.2 为日期字段接入 FAF 风格操作符集合，并为 `kind` 定义专用 `is / is not + 类型下拉` 配置
- [x] 1.3 补充 `comments`、`script` 的暂不支持状态与对应本地化文案

## 2. 接入规则校验与主窗口阻塞反馈

- [x] 2.1 新增规则校验模型，区分 `valid`、`unsupported`、`invalid`
- [x] 2.2 更新 `SearchRuleRowView`，根据能力矩阵切换编辑器、显示置灰项和行内阻塞提示
- [x] 2.3 更新 `SearchRulesViewController`，聚合规则状态并向外暴露是否允许搜索与首条阻塞原因
- [x] 2.4 更新 `SearchFormViewController`，在规则无效时禁用 `Find` 并复用底部状态区域显示原因

## 3. 实现日期与 Kind 的执行能力

- [x] 3.1 扩展搜索执行层的日期比较语义，支持 `on or after`、`on or before`、`within the last`、`today`、`yesterday`
- [x] 3.2 新增文件种类归一化能力，并为 `kind is / is not` 提供稳定枚举匹配
- [x] 3.3 确保规则恢复与本地执行链路使用稳定值，而不是依赖展示文案

## 4. 补齐测试与验证

- [x] 4.1 为能力矩阵、规则校验、日期语义和 `kind` 归一化补齐单元测试
- [x] 4.2 为规则编辑器与主窗口阻塞行为补齐视图/控制器测试
- [x] 4.3 运行相关测试，确认无效规则不会发起搜索，合法规则仍可正常执行
