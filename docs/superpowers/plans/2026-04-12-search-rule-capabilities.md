# FileHound Search Rule Capabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the find-window rule editor with FAF-style date and kind criteria, block unsupported or invalid rules before search, and keep OpenSpec tasks in sync while preserving working local search execution.

**Architecture:** Add a single rule-capability source in `SearchRuleCatalog` and a dedicated validation layer so the UI no longer guesses which field/operator/value combinations work. Extend the executor with explicit date semantics and a small file-kind normalizer so `Kind is / is not` compares stable ids instead of display text, then wire the validation summary into the find window to disable `Find` when rules are blocked.

**Tech Stack:** Swift, AppKit, SnapKit, Foundation, UniformTypeIdentifiers, Testing/XCTest, OpenSpec

---

## File Map

- Modify: `FileHound/Modules/SearchRules/SearchRuleCatalog.swift`
  Responsibility: become the single source of field/operator/value-editor capability metadata, including supported vs unsupported menu items.
- Create: `FileHound/Modules/SearchRules/SearchRuleValidation.swift`
  Responsibility: define rule validation result types, validation summary, and field/value validation helpers.
- Modify: `FileHound/Modules/SearchRules/SearchRuleRowView.swift`
  Responsibility: render disabled menu items, swap in date/kind-specific editors, and show inline blocking messages.
- Modify: `FileHound/Modules/SearchRules/SearchRulesViewController.swift`
  Responsibility: aggregate row validation, expose `canSearch` and first blocking message, and preserve existing selection callbacks.
- Modify: `FileHound/Modules/SearchWindow/SearchFormViewController.swift`
  Responsibility: disable `Find`, surface the first blocking reason, and stop invalid rules from reaching `SearchWorkflowController.start`.
- Modify: `FileHound/SearchEngine/Execution/SearchExecutor.swift`
  Responsibility: execute FAF-style date operators and kind matching, using stable value ids rather than localized labels.
- Create: `FileHound/SearchEngine/Execution/FileKindResolver.swift`
  Responsibility: normalize filesystem entries into stable kind ids used by the `Kind` rule.
- Modify: `FileHound/Resources/Localization/en.lproj/Localizable.strings`
  Responsibility: add date-operator, kind-option, and unsupported/invalid-rule strings.
- Modify: `FileHound/Resources/Localization/zh-Hans.lproj/Localizable.strings`
  Responsibility: simplified Chinese strings for new operators, kinds, and blocking messages.
- Modify: `FileHound/Resources/Localization/zh-Hant.lproj/Localizable.strings`
  Responsibility: traditional Chinese strings for new operators, kinds, and blocking messages.
- Create: `FileHoundTests/SearchRules/SearchRuleCatalogTests.swift`
  Responsibility: lock capability-matrix behavior for date, kind, and unsupported fields.
- Create: `FileHoundTests/SearchRules/SearchRuleValidationTests.swift`
  Responsibility: lock validation results for invalid and unsupported combinations.
- Modify: `FileHoundTests/SearchWindow/SearchRulesViewControllerTests.swift`
  Responsibility: verify row/editor switching, inline warnings, and aggregated blocking state.
- Modify: `FileHoundTests/SearchWindow/SearchFormViewControllerTests.swift`
  Responsibility: verify invalid rules disable `Find` and do not enter searching state.
- Modify: `FileHoundTests/SearchEngine/SearchExecutorTests.swift`
  Responsibility: verify new date semantics and kind matching in the local executor path.
- Create: `FileHoundTests/SearchEngine/FileKindResolverTests.swift`
  Responsibility: verify common UTType/extension mappings and `any` handling for kind ids.
- Modify: `openspec/changes/align-search-rule-capabilities/tasks.md`
  Responsibility: mark OpenSpec tasks complete as each batch lands.

### Task 1: Lock the Capability Matrix Contract

**Files:**
- Create: `FileHoundTests/SearchRules/SearchRuleCatalogTests.swift`
- Modify: `FileHound/Modules/SearchRules/SearchRuleCatalog.swift`
- Modify: `FileHound/Resources/Localization/en.lproj/Localizable.strings`
- Modify: `FileHound/Resources/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `FileHound/Resources/Localization/zh-Hant.lproj/Localizable.strings`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import FileHound

struct SearchRuleCatalogTests {
    @Test
    func dateFieldsExposeFafStyleOperators() {
        let operators = SearchRuleField.lastModifiedDate.definition.operators.map(\.op)

        #expect(operators == [
            .isOnOrAfter,
            .isOnOrBefore,
            .isExactly,
            .isWithinTheLast,
            .isToday,
            .isYesterday
        ])
    }

    @Test
    func kindUsesDedicatedOperatorsAndChoiceEditor() {
        let definition = SearchRuleField.kind.definition

        #expect(definition.operators.map(\.op) == [.isExactly, .isNot])
        #expect(definition.valueEditor.debugStyle == "choice")
        #expect(definition.valueEditor.debugOptionIDs.contains("kind.any"))
        #expect(definition.valueEditor.debugOptionIDs.contains("kind.application"))
    }

    @Test
    func unsupportedFieldsStayVisibleButBlocked() {
        let comments = SearchRuleField.comments.definition

        #expect(comments.isSupported == false)
        #expect(comments.blockingMessageKey == "search_rule.unsupported.pending")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchRuleCatalogTests`

Expected: FAIL because the new operators, choice editor helpers, and unsupported metadata do not exist yet.

- [ ] **Step 3: Write the minimal implementation**

```swift
enum SearchRuleOperator: String, CaseIterable, Codable, Sendable {
    case contains
    case containsPhrase
    case beginsWith
    case endsWith
    case isExactly
    case isNot
    case doesNotContain
    case containsWords
    case matchesPattern
    case containsAnyOf
    case beginsWithAnyOf
    case endsWithAnyOf
    case isAnyOf
    case matchesRegex
    case doesNotMatchRegex
    case isGreaterThan
    case isLessThan
    case isOnOrBefore
    case isOnOrAfter
    case isWithinTheLast
    case isToday
    case isYesterday
}

struct SearchRuleOperatorDefinition: Sendable {
    let op: SearchRuleOperator
    let isSupported: Bool
}

enum SearchRuleValueEditorKind: Equatable, Sendable {
    case text
    case number
    case date
    case relativeDate(units: [SearchRuleRelativeDateUnit])
    case none
    case toggle(falseLabel: String, trueLabel: String)
    case choice(options: [SearchRuleChoiceOption])
}

struct SearchRuleChoiceOption: Equatable, Sendable {
    let id: String
    let titleKey: String
}

struct SearchRuleFieldDefinition: Sendable {
    let operators: [SearchRuleOperatorDefinition]
    let valueEditor: SearchRuleValueEditorKind
    let placeholder: String?
    let blockingMessageKey: String?

    var isSupported: Bool {
        operators.contains(where: \.isSupported)
    }
}
```

```swift
case .lastModifiedDate, .createdDate, .lastOpenedDate:
    return SearchRuleFieldDefinition(
        operators: [
            .init(op: .isOnOrAfter, isSupported: true),
            .init(op: .isOnOrBefore, isSupported: true),
            .init(op: .isExactly, isSupported: true),
            .init(op: .isWithinTheLast, isSupported: true),
            .init(op: .isToday, isSupported: true),
            .init(op: .isYesterday, isSupported: true)
        ],
        valueEditor: .date,
        placeholder: L10n.string("search_rule.placeholder.date"),
        blockingMessageKey: nil
    )
case .kind:
    return SearchRuleFieldDefinition(
        operators: [
            .init(op: .isExactly, isSupported: true),
            .init(op: .isNot, isSupported: true)
        ],
        valueEditor: .choice(options: SearchRuleChoiceOption.kindOptions),
        placeholder: nil,
        blockingMessageKey: nil
    )
case .comments, .script:
    return SearchRuleFieldDefinition(
        operators: [
            .init(op: .containsPhrase, isSupported: false)
        ],
        valueEditor: .text,
        placeholder: L10n.string("search_rule.placeholder.value"),
        blockingMessageKey: "search_rule.unsupported.pending"
    )
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchRuleCatalogTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add FileHound/Modules/SearchRules/SearchRuleCatalog.swift \
  FileHound/Resources/Localization/en.lproj/Localizable.strings \
  FileHound/Resources/Localization/zh-Hans.lproj/Localizable.strings \
  FileHound/Resources/Localization/zh-Hant.lproj/Localizable.strings \
  FileHoundTests/SearchRules/SearchRuleCatalogTests.swift \
  openspec/changes/align-search-rule-capabilities/tasks.md
git commit -m "feat: add search rule capability matrix"
```

### Task 2: Validate Rules in the Editor and Block Invalid Searches

**Files:**
- Create: `FileHound/Modules/SearchRules/SearchRuleValidation.swift`
- Modify: `FileHound/Modules/SearchRules/SearchRuleRowView.swift`
- Modify: `FileHound/Modules/SearchRules/SearchRulesViewController.swift`
- Modify: `FileHound/Modules/SearchWindow/SearchFormViewController.swift`
- Modify: `FileHoundTests/SearchWindow/SearchRulesViewControllerTests.swift`
- Modify: `FileHoundTests/SearchWindow/SearchFormViewControllerTests.swift`
- Create: `FileHoundTests/SearchRules/SearchRuleValidationTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import FileHound

struct SearchRuleValidationTests {
    @Test
    func kindIsNotAnyIsInvalid() {
        let validator = SearchRuleValidator()
        let result = validator.validate(
            SearchRuleSelection(field: .kind, operator: .isNot, value: "kind.any")
        )

        #expect(result == .invalid(messageKey: "search_rule.validation.kind_not_any"))
    }

    @Test
    func unsupportedFieldStaysUnsupported() {
        let validator = SearchRuleValidator()
        let result = validator.validate(
            SearchRuleSelection(field: .comments, operator: .containsPhrase, value: "note")
        )

        #expect(result == .unsupported(messageKey: "search_rule.unsupported.pending"))
    }
}
```

```swift
@MainActor
@Test
func invalidRulesExposeBlockingSummary() {
    let controller = SearchRulesViewController()
    _ = controller.view

    controller.applySelections([
        SearchRuleSelection(field: .kind, operator: .isNot, value: "kind.any")
    ])

    #expect(controller.debugCanSearch == false)
    #expect(controller.debugBlockingMessage == L10n.string("search_rule.validation.kind_not_any"))
}
```

```swift
@MainActor
@Test
func invalidRulesDisableFindAndKeepEditingState() {
    let controller = SearchFormViewController()
    _ = controller.view

    controller.applySearchSessionSnapshot(
        SearchSessionSnapshot(
            criteria: SearchCriteriaSnapshot(
                scope: controller.debugCurrentSearchSessionSnapshot.criteria.scope,
                rules: [SearchRuleSelection(field: .kind, operator: .isNot, value: "kind.any")]
            )
        )
    )

    #expect(controller.debugPrimaryActionEnabled == false)
    #expect(controller.debugStatusText == L10n.string("search_rule.validation.kind_not_any"))

    controller.debugTriggerPrimaryAction()

    #expect(controller.debugPrimaryActionTitle == L10n.string("search_window.action.find"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchRuleValidationTests -only-testing:FileHoundTests/SearchRulesViewControllerTests -only-testing:FileHoundTests/SearchFormViewControllerTests`

Expected: FAIL because there is no validation layer, no blocking summary, and the form does not disable `Find`.

- [ ] **Step 3: Write the minimal implementation**

```swift
enum SearchRuleValidationResult: Equatable, Sendable {
    case valid
    case unsupported(messageKey: String)
    case invalid(messageKey: String)

    var blockingMessage: String? {
        switch self {
        case .valid:
            return nil
        case .unsupported(let key), .invalid(let key):
            return L10n.string(key)
        }
    }
}

struct SearchRuleValidationSummary: Equatable, Sendable {
    let canSearch: Bool
    let firstBlockingMessage: String?
}

struct SearchRuleValidator: Sendable {
    func validate(_ selection: SearchRuleSelection) -> SearchRuleValidationResult {
        let definition = selection.field.definition

        if definition.isSupported == false {
            return .unsupported(messageKey: definition.blockingMessageKey ?? "search_rule.unsupported.pending")
        }
        if selection.field == .kind, selection.operator == .isNot, selection.value == "kind.any" {
            return .invalid(messageKey: "search_rule.validation.kind_not_any")
        }
        return .valid
    }
}
```

```swift
final class SearchRuleRowView: NSView {
    private let validationLabel = NSTextField(labelWithString: "")
    private var validationResult: SearchRuleValidationResult = .valid

    func applyValidation(_ result: SearchRuleValidationResult) {
        validationResult = result
        validationLabel.stringValue = result.blockingMessage ?? ""
        validationLabel.isHidden = result == .valid
    }
}
```

```swift
final class SearchRulesViewController: NSViewController {
    private let validator = SearchRuleValidator()

    var validationSummary: SearchRuleValidationSummary {
        let results = rows.map { validator.validate($0.selection) }
        let firstBlocking = results.compactMap(\.blockingMessage).first
        return .init(canSearch: firstBlocking == nil, firstBlockingMessage: firstBlocking)
    }
}
```

```swift
private func render(_ state: SearchWindowState) {
    let summary = rulesViewController.validationSummary
    primaryButton.isEnabled = state.isEditingEnabled && summary.canSearch
    statusLabel.stringValue = summary.firstBlockingMessage ?? state.statusText
}

@objc
private func primaryButtonPressed() {
    guard rulesViewController.validationSummary.canSearch else {
        render(state)
        return
    }
    // existing start/cancel switch follows
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/SearchRuleValidationTests -only-testing:FileHoundTests/SearchRulesViewControllerTests -only-testing:FileHoundTests/SearchFormViewControllerTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add FileHound/Modules/SearchRules/SearchRuleValidation.swift \
  FileHound/Modules/SearchRules/SearchRuleRowView.swift \
  FileHound/Modules/SearchRules/SearchRulesViewController.swift \
  FileHound/Modules/SearchWindow/SearchFormViewController.swift \
  FileHoundTests/SearchRules/SearchRuleValidationTests.swift \
  FileHoundTests/SearchWindow/SearchRulesViewControllerTests.swift \
  FileHoundTests/SearchWindow/SearchFormViewControllerTests.swift \
  openspec/changes/align-search-rule-capabilities/tasks.md
git commit -m "feat: block invalid search rules in find window"
```

### Task 3: Execute FAF-Style Date and Kind Rules

**Files:**
- Create: `FileHound/SearchEngine/Execution/FileKindResolver.swift`
- Modify: `FileHound/SearchEngine/Execution/SearchExecutor.swift`
- Modify: `FileHoundTests/SearchEngine/SearchExecutorTests.swift`
- Create: `FileHoundTests/SearchEngine/FileKindResolverTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import FileHound

struct FileKindResolverTests {
    @Test
    func resolvesCommonKindsFromPathAndDirectoryState() {
        let resolver = FileKindResolver()

        #expect(resolver.kindID(forPath: "/tmp/Preview.app", isDirectory: true) == "kind.application")
        #expect(resolver.kindID(forPath: "/tmp/archive.zip", isDirectory: false) == "kind.archive")
        #expect(resolver.kindID(forPath: "/tmp/readme.txt", isDirectory: false) == "kind.plain-text")
    }
}
```

```swift
@Test
func executeSupportsFafDateOperatorsAndKindMatching() throws {
    let fixture = try TemporaryFixtureTree.make { builder in
        try builder.file("Preview.app/Contents/Info.plist", contents: "plist")
        try builder.file("today.txt", contents: "hello")
    }

    let now = ISO8601DateFormatter().date(from: "2026-04-12T10:00:00Z")!
    let executor = SearchExecutor(
        provider: LocalFilesystemProvider(),
        spotlightSearchService: SpotlightSearchService(runQuery: { _, _ in [] }),
        nowProvider: { now }
    )

    let kindResult = executor.execute(
        request: SearchRequest(
            scopeDescription: "Root",
            rootPath: fixture.path,
            rules: [SearchRuleSelection(field: .kind, operator: .isExactly, value: "kind.application")]
        ),
        options: SearchExecutionOptions(includeSpotlightResults: false)
    )

    #expect(kindResult.items.contains { $0.path.hasSuffix("/Preview.app") })
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/FileKindResolverTests -only-testing:FileHoundTests/SearchExecutorTests`

Expected: FAIL because `FileKindResolver` and the new executor semantics do not exist.

- [ ] **Step 3: Write the minimal implementation**

```swift
struct FileKindResolver: Sendable {
    func kindID(forPath path: String, isDirectory: Bool) -> String {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        if isDirectory {
            if ext == "app" { return "kind.application" }
            if ["bundle", "framework", "plugin"].contains(ext) { return "kind.package" }
            return "kind.folder"
        }

        switch ext {
        case "txt", "md", "json", "xml":
            return "kind.plain-text"
        case "zip", "tar", "gz", "dmg":
            return ext == "dmg" ? "kind.disk-image" : "kind.archive"
        case "pdf":
            return "kind.pdf"
        case "jpg", "jpeg", "png", "gif", "webp", "heic":
            return "kind.image"
        case "mp3", "wav", "m4a":
            return "kind.audio"
        case "mp4", "mov", "mkv":
            return "kind.video"
        default:
            return "kind.file"
        }
    }
}
```

```swift
private func compareDate(_ candidate: Date?, using rule: SearchRuleSelection) -> Bool {
    guard let candidate else { return false }
    let calendar = Calendar(identifier: .gregorian)

    switch rule.operator {
    case .isExactly:
        guard let target = parseDate(from: rule.value) else { return false }
        return calendar.isDate(candidate, inSameDayAs: target)
    case .isOnOrAfter:
        guard let target = parseDate(from: rule.value) else { return false }
        return candidate >= calendar.startOfDay(for: target)
    case .isOnOrBefore:
        guard let target = parseDate(from: rule.value) else { return false }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: target))!
        return candidate < nextDay
    case .isToday:
        return calendar.isDateInToday(candidate)
    case .isYesterday:
        return calendar.isDateInYesterday(candidate)
    case .isWithinTheLast:
        guard let relative = parseRelativeDate(from: rule.value) else { return false }
        return candidate >= relative.cutoff(now: nowProvider())
    default:
        return false
    }
}
```

```swift
case .kind:
    let kindID = fileKindResolver.kindID(forPath: entry.path, isDirectory: entry.isDirectory)
    switch rule.operator {
    case .isExactly:
        return rule.value == "kind.any" || kindID == rule.value
    case .isNot:
        return rule.value != "kind.any" && kindID != rule.value
    default:
        return false
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme FileHound -destination 'platform=macOS' -only-testing:FileHoundTests/FileKindResolverTests -only-testing:FileHoundTests/SearchExecutorTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add FileHound/SearchEngine/Execution/FileKindResolver.swift \
  FileHound/SearchEngine/Execution/SearchExecutor.swift \
  FileHoundTests/SearchEngine/FileKindResolverTests.swift \
  FileHoundTests/SearchEngine/SearchExecutorTests.swift \
  openspec/changes/align-search-rule-capabilities/tasks.md
git commit -m "feat: execute faf-style date and kind rules"
```

### Task 4: Run Focused Verification and Close the OpenSpec Loop

**Files:**
- Modify: `openspec/changes/align-search-rule-capabilities/tasks.md`
- Modify: `docs/superpowers/specs/2026-04-12-search-rule-capabilities-design.md` (only if implementation reveals a spec mismatch)

- [ ] **Step 1: Run the focused verification suite**

Run:

```bash
xcodebuild test -scheme FileHound -destination 'platform=macOS' \
  -only-testing:FileHoundTests/SearchRuleCatalogTests \
  -only-testing:FileHoundTests/SearchRuleValidationTests \
  -only-testing:FileHoundTests/SearchRulesViewControllerTests \
  -only-testing:FileHoundTests/SearchFormViewControllerTests \
  -only-testing:FileHoundTests/SearchExecutorTests \
  -only-testing:FileHoundTests/FileKindResolverTests
```

Expected: PASS for all targeted suites.

- [ ] **Step 2: Mark the OpenSpec tasks complete**

```markdown
- [x] 1.1 在 `SearchRuleCatalog` 中引入字段能力矩阵，统一声明字段标题、值编辑器、操作符集合、支持状态与阻塞提示
- [x] 1.2 为日期字段接入 FAF 风格操作符集合，并为 `kind` 定义专用 `is / is not + 类型下拉` 配置
- [x] 1.3 补充 `comments`、`script` 的暂不支持状态与对应本地化文案
- [x] 2.1 新增规则校验模型，区分 `valid`、`unsupported`、`invalid`
- [x] 2.2 更新 `SearchRuleRowView`，根据能力矩阵切换编辑器、显示置灰项和行内阻塞提示
- [x] 2.3 更新 `SearchRulesViewController`，聚合规则状态并向外暴露是否允许搜索与首条阻塞原因
- [x] 2.4 更新 `SearchFormViewController`，在规则无效时禁用 `Find` 并复用底部状态区域显示原因
- [x] 3.1 扩展搜索执行层的日期比较语义，支持 `on or after`、`on or before`、`within the last`、`today`、`yesterday`
- [x] 3.2 新增文件种类归一化能力，并为 `kind is / is not` 提供稳定枚举匹配
- [x] 3.3 确保规则恢复与本地执行链路使用稳定值，而不是依赖展示文案
- [x] 4.1 为能力矩阵、规则校验、日期语义和 `kind` 归一化补齐单元测试
- [x] 4.2 为规则编辑器与主窗口阻塞行为补齐视图/控制器测试
- [x] 4.3 运行相关测试，确认无效规则不会发起搜索，合法规则仍可正常执行
```

- [ ] **Step 3: Commit the finished batch**

```bash
git add openspec/changes/align-search-rule-capabilities/tasks.md \
  docs/superpowers/plans/2026-04-12-search-rule-capabilities.md
git commit -m "docs: finish search rule capabilities plan"
```
