# FileHound 搜索条件能力矩阵设计

日期：2026-04-12  
状态：已确认，待评审

## 1. 背景

当前 FileHound 的搜索条件编辑器已经暴露出较完整的字段与操作符，但实现存在明显失配：

- UI 可选项多于底层真实支持能力
- 日期条件仍停留在 `is before / is after / is exactly`，与目标参考体验不一致
- `kind` 字段当前只是简化文本，无法承载 FAF 风格类型筛选
- `comments`、`script` 等字段已出现在 UI 中，但没有可交付的执行能力
- 规则是否合法、是否支持，分散在 UI、执行层和隐含约定里，没有单一真相来源

本轮目标不是继续增加更多“看起来能选”的条件，而是把“什么可以选、什么能执行、什么要禁用”收口成清晰、可维护、可测试的一套能力矩阵。

## 2. 本轮目标

- 日期条件改为 FAF 风格操作符与交互
- `kind` 条件支持 FAF 风格的 `is / is not + 类型下拉`
- 建立统一的搜索条件能力矩阵，成为 UI 与校验的唯一数据源
- 全量审计当前字段与操作符，不能稳定交付的项统一置灰
- 用户在遇到暂不支持或无效组合时，得到明确提示，而不是发起无效搜索
- 在“本地执行正确”前提下开放能力，Spotlight 与编译层允许降级，不作为本轮拦截门槛

## 3. 范围

### 3.1 包含范围

- 搜索条件字段、操作符和值编辑器定义重构
- 日期操作符与值编辑器重构
- `kind` 条件模型、类型枚举与执行能力
- 不支持条件置灰与提示
- 无效组合校验与搜索按钮禁用
- 对应单元测试、视图测试与搜索执行测试

### 3.2 不包含范围

- 新增脚本规则执行器
- Finder 注释读写与索引能力
- 完整重写 `QueryCompiler` 以覆盖全部新规则
- 依赖 Spotlight 元数据实现的高保真 `kind` 搜索

## 4. 支持标准

本轮按“平衡”标准判定功能是否开放：

- 本地遍历执行结果必须正确
- 规则保存、恢复和界面回显必须稳定
- Spotlight 可降级，不作为开放门槛
- 查询编译层暂不要求与新 UI 枚举完全一致，只要不会破坏当前主搜索链路

这意味着本轮的唯一硬标准是：用户在主搜索窗口里创建规则后，本地搜索结果要可靠，且 UI 不允许进入明显错误的状态。

## 5. 架构方案

### 5.1 单一能力矩阵

在 `SearchRuleCatalog` 中建立统一能力矩阵，作为以下信息的唯一来源：

- 字段标题
- 字段可见性
- 字段对应的值编辑器
- 字段支持的操作符集合
- 每个操作符当前是 `supported` 还是 `unsupported`
- 不支持时的提示文案 key
- 该字段是否参与全局执行行为

UI 不再根据字段类型写死操作符，不再隐式猜测某个组合是否可用，而是完全根据能力矩阵渲染。

### 5.2 校验模型

新增规则校验结果模型，用于区分“可执行”“暂不支持”“用户组合无效”三种状态：

- `valid`
- `unsupported(reasonKey)`
- `invalid(reasonKey)`

其职责边界如下：

- 能力矩阵负责声明哪些组合理论上开放
- 校验器负责判断当前具体值是否有效
- 执行器只处理已判定为 `valid` 的规则

### 5.3 UI 与执行层边界

- `SearchRuleRowView` 负责单行菜单渲染、编辑器切换、行内提示
- `SearchRulesViewController` 负责聚合所有行的校验状态
- `SearchFormViewController` 负责决定是否允许发起搜索，并复用现有底部状态文案区域
- `SearchExecutor` 只扩展实际执行所需的日期与 `kind` 逻辑，不承担 UI 可用性判断职责

## 6. 字段与操作符能力矩阵

### 6.1 正式支持并开放

以下字段在本轮保持可用：

- `name`
- `extensionName`
- `nameWithoutExtension`
- `lastModifiedDate`
- `createdDate`
- `lastOpenedDate`
- `fileSize`
- `kind`
- `tag`
- `textContent`
- `path`
- `folderNames`
- `caseSensitive`
- `diacriticsSensitive`
- `invisibleItems`
- `packageContents`
- `trashedContents`
- `limitFolderDepth`
- `limitAmount`

### 6.2 保留但置灰

以下字段保留在菜单中，但显示为暂不支持：

- `comments`
- `script`

用户不能从菜单主动选择这些字段；若从内部快照或调试入口载入到这些字段，对应行显示提示并阻止搜索。

## 7. 日期条件设计

### 7.1 操作符集合

日期字段统一切换到以下 6 个 FAF 风格操作符：

- `is on or after`
- `is on or before`
- `is exactly`
- `is within the last`
- `is today`
- `is yesterday`

旧的 `is before / is after` 不再作为产品可见选项保留。由于产品尚未上线，不需要兼容旧用户语义，直接使用新选项。

### 7.2 语义定义

- `is on or after`：`candidate >= 目标日 00:00:00`
- `is on or before`：`candidate < 目标日次日 00:00:00`
- `is exactly`：候选时间与目标日处于同一自然日
- `is within the last`：`candidate >= now - 相对区间`
- `is today`：候选时间与当前自然日一致
- `is yesterday`：候选时间与昨天自然日一致

所有日期比较都使用当前系统时区与 Gregorian 日历，与 macOS 常规文件时间语义一致。

### 7.3 值编辑器

按操作符动态切换值编辑器：

- `is on or after / is on or before / is exactly`
  - 使用日期输入
- `is within the last`
  - 使用“数值 + 单位”编辑器
  - 首版单位支持：`天 / 周 / 月`
- `is today / is yesterday`
  - 不显示值输入控件

### 7.4 无效值规则

以下情况判定为无效组合：

- `is within the last` 但未填写数值
- `is within the last` 的数值不是正整数
- `is within the last` 未选择单位
- 需要日期输入的操作符但日期为空或格式不可解析

无效时不发起搜索，直接在行内和底部状态区提示。

## 8. Kind 条件设计

### 8.1 UI 结构

`kind` 选中后，交互固定为 FAF 风格三段式：

1. 字段：`Kind`
2. 操作符：`is / is not`
3. 值：类型下拉

`kind` 不再复用通用文本操作符集合。

### 8.2 类型列表

类型下拉首版使用固定枚举，并尽量对齐 FAF 的顺序与命名：

- `any`
- `Alias or Symlink`
- `AppleScript`
- `Application`
- `Archive`
- `Audio`
- `Directory`
- `Disk Image`
- `eBook`
- `File`
- `Finder Alias`
- `Folder`
- `Font`
- `Image`
- `Package (Bundle)`
- `PDF`
- `Plain Text`
- `Presentation`
- `Spreadsheet`
- `Symlink`
- `Text`
- `UNIX executable`
- `Video`
- `Word & Pages`

### 8.3 执行语义

为了避免依赖本地化显示文本，执行层新增规范化的 `kind` 枚举解析：

1. 先识别确定性类型：
   - 文件夹
   - 目录型条目
   - 包
   - 符号链接
2. 再结合路径扩展名、UTType 和系统可推断的文件类型信息归一化到固定枚举
3. 最后对枚举做 `is / is not` 判断

结果列表里的 `kind` 文本仍可继续作为展示文案，但搜索条件判断不得再直接依赖展示字符串。

内部使用稳定的枚举 id，界面文案再做本地化展示，避免因为语言切换导致规则保存值失效。

### 8.4 首版映射约束

为避免实现阶段产生歧义，首版先明确以下映射规则：

- `Folder`：普通文件夹条目
- `Directory`：首版与 `Folder` 视为同义类型，保证与 FAF 菜单可见项一致
- `Package (Bundle)`：被识别为包的目录型条目
- `File`：非目录、非包的普通文件
- `Symlink`：符号链接
- `Finder Alias`：Finder Alias 文件
- `Alias or Symlink`：`Finder Alias` 与 `Symlink` 的并集
- `Text`：文本大类，包含 `Plain Text` 与可识别的富文本/文稿文本格式
- `Plain Text`：纯文本文件
- `Word & Pages`：可识别的 Word / Pages 文稿

其余类型优先按 UTType 大类或稳定扩展名映射；无法可靠判定时，回退到更宽泛的大类，而不是误判成错误的细分类。

### 8.5 `any` 的规则

- `Kind is any`：视为不过滤，恒成立
- `Kind is not any`：视为无效组合

`Kind is not any` 出现时：

- 行内显示提示
- 底部状态显示原因
- `Find` 按钮禁用
- 不发起搜索

## 9. 不支持与无效状态交互

### 9.1 菜单行为

- 菜单里保留所有字段与规划中的操作符
- 暂不支持的字段或操作符显示为置灰
- 置灰项不可被用户主动选择

### 9.2 行内提示

当行内规则处于 `unsupported` 或 `invalid` 状态时，规则行显示简短提示文案。提示文案遵循以下方向：

- 暂不支持：`暂不支持，等待开放`
- 无效组合：给出具体原因，例如：
  - `请为“最近时间”填写正整数`
  - `Kind 不能使用 is not any`

### 9.3 搜索入口行为

`SearchRulesViewController` 聚合所有规则状态后，对外提供：

- 当前规则数组
- 当前是否允许搜索
- 首条阻塞原因文案

`SearchFormViewController` 使用该聚合结果更新现有界面：

- 底部 `statusLabel` 在编辑态显示首条阻塞原因
- `Find` 按钮禁用
- 不调用 `workflowController.start(...)`

如果全部规则合法，恢复现有状态文案和搜索行为。

## 10. 保存与恢复

虽然当前尚无线上用户，但规则仍需要在本地会话恢复与保存搜索中稳定工作。

要求如下：

- 合法规则完整保存与恢复
- 不支持字段或无效组合在恢复后必须明确显示阻塞状态，不能静默丢失
- UI 必须保持原始选择，方便后续人工调整

这意味着恢复逻辑不能擅自把无效组合“改成最近可用值”，否则会让用户失去对当前状态的判断。

## 11. 本轮测试策略

### 11.1 单元测试

- 日期 6 个操作符的语义测试
- `is within the last` 数值与单位校验测试
- `kind` 类型归一化映射测试
- `Kind is any` 与 `Kind is not any` 的行为测试
- `comments` / `script` 被标记为 `unsupported` 的测试

### 11.2 视图测试

- 切换字段后操作符菜单正确刷新
- 日期字段按操作符切换编辑器
- `kind` 字段切换为 `is / is not + 类型下拉`
- 暂不支持字段在菜单中存在但置灰
- 载入无效或不支持规则后，行内提示与禁用状态正确

### 11.3 搜索执行测试

- 日期条件在本地遍历模式下结果正确
- `kind is / is not` 条件结果正确
- 非法规则不会发起搜索
- 阻塞原因会透传到搜索表单状态区

## 12. 风险与约束

- `kind` 的高保真映射依赖本地文件类型信息，首版应优先保证常见类型正确，不追求覆盖所有稀有文档格式
- 日期相对时间表达式涉及当前时间，测试必须冻结时钟或注入时间源，避免脆弱断言
- 能力矩阵一旦成为唯一真相来源，后续新增字段必须同步补齐校验与测试，否则会重新产生失配

## 13. 完成标准

- 日期字段展示 FAF 风格 6 个操作符，并按操作符切换正确的值编辑器
- `kind` 字段支持 FAF 风格 `is / is not + 类型下拉`
- `comments` 与 `script` 在菜单中保留但置灰
- 无效规则与不支持规则均有明确提示，且不能发起搜索
- 主搜索窗口只对 `valid` 规则执行搜索
- 新增测试覆盖日期、`kind`、置灰状态与阻塞行为
