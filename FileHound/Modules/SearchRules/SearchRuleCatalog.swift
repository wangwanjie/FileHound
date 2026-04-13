import Foundation

enum SearchRuleField: String, CaseIterable, Codable, Sendable {
    case name = "Name"
    case extensionName = "Extension"
    case nameWithoutExtension = "Name without Extension"
    case lastModifiedDate = "Last modified date"
    case createdDate = "Created date"
    case lastOpenedDate = "Last opened date"
    case fileSize = "File size"
    case kind = "Kind"
    case tag = "Tag"
    case comments = "Comments"
    case textContent = "Text content"
    case path = "Path"
    case folderNames = "Folder names"
    case script = "Script"
    case caseSensitive = "Case sensitive"
    case diacriticsSensitive = "Diacritics sensitive"
    case invisibleItems = "Invisible items"
    case packageContents = "Package contents"
    case trashedContents = "Trashed contents"
    case limitFolderDepth = "Limit folder depth"
    case limitAmount = "Limit amount"

    var localizedTitle: String {
        switch self {
        case .name:
            return L10n.string("search_rule.field.name")
        case .extensionName:
            return L10n.string("search_rule.field.extension")
        case .nameWithoutExtension:
            return L10n.string("search_rule.field.name_without_extension")
        case .lastModifiedDate:
            return L10n.string("search_rule.field.last_modified_date")
        case .createdDate:
            return L10n.string("search_rule.field.created_date")
        case .lastOpenedDate:
            return L10n.string("search_rule.field.last_opened_date")
        case .fileSize:
            return L10n.string("search_rule.field.file_size")
        case .kind:
            return L10n.string("search_rule.field.kind")
        case .tag:
            return L10n.string("search_rule.field.tag")
        case .comments:
            return L10n.string("search_rule.field.comments")
        case .textContent:
            return L10n.string("search_rule.field.text_content")
        case .path:
            return L10n.string("search_rule.field.path")
        case .folderNames:
            return L10n.string("search_rule.field.folder_names")
        case .script:
            return L10n.string("search_rule.field.script")
        case .caseSensitive:
            return L10n.string("search_rule.field.case_sensitive")
        case .diacriticsSensitive:
            return L10n.string("search_rule.field.diacritics_sensitive")
        case .invisibleItems:
            return L10n.string("search_rule.field.invisible_items")
        case .packageContents:
            return L10n.string("search_rule.field.package_contents")
        case .trashedContents:
            return L10n.string("search_rule.field.trashed_contents")
        case .limitFolderDepth:
            return L10n.string("search_rule.field.limit_folder_depth")
        case .limitAmount:
            return L10n.string("search_rule.field.limit_amount")
        }
    }

    var definition: SearchRuleFieldDefinition {
        switch self {
        case .lastModifiedDate, .createdDate, .lastOpenedDate:
            return SearchRuleFieldDefinition(
                operators: [
                    .init(op: .isOnOrAfter),
                    .init(op: .isOnOrBefore),
                    .init(op: .isExactly),
                    .init(op: .isWithinTheLast),
                    .init(op: .isToday),
                    .init(op: .isYesterday)
                ],
                valueEditor: .date,
                placeholder: L10n.string("search_rule.placeholder.date"),
                editorOverrides: [
                    .isWithinTheLast: .relativeDate(units: SearchRuleRelativeDateUnit.allCases),
                    .isToday: .none,
                    .isYesterday: .none
                ],
                placeholderOverrides: [
                    .isWithinTheLast: L10n.string("search_rule.placeholder.amount"),
                    .isToday: nil,
                    .isYesterday: nil
                ]
            )
        case .fileSize, .limitFolderDepth, .limitAmount:
            return SearchRuleFieldDefinition(
                operators: [.init(op: .isExactly), .init(op: .isGreaterThan), .init(op: .isLessThan)],
                valueEditor: .number,
                placeholder: L10n.string("search_rule.placeholder.value")
            )
        case .kind:
            return SearchRuleFieldDefinition(
                operators: [.init(op: .isExactly), .init(op: .isNot)],
                valueEditor: .choice(options: SearchRuleChoiceOption.kindOptions),
                placeholder: nil
            )
        case .caseSensitive, .diacriticsSensitive:
            return SearchRuleFieldDefinition(
                operators: [.init(op: .isExactly)],
                valueEditor: .toggle(
                    falseLabel: L10n.string("search_rule.toggle.off"),
                    trueLabel: L10n.string("search_rule.toggle.on")
                ),
                placeholder: nil
            )
        case .invisibleItems, .packageContents, .trashedContents:
            return SearchRuleFieldDefinition(
                operators: [.init(op: .isExactly)],
                valueEditor: .toggle(
                    falseLabel: L10n.string("search_rule.toggle.exclude"),
                    trueLabel: L10n.string("search_rule.toggle.include")
                ),
                placeholder: nil
            )
        case .comments:
            return SearchRuleFieldDefinition(
                operators: SearchRuleOperatorDefinition.unsupported(defaultTextOperators),
                valueEditor: .text,
                placeholder: L10n.string("search_rule.placeholder.comment"),
                blockingMessageKey: "search_rule.unsupported.pending"
            )
        case .script:
            return SearchRuleFieldDefinition(
                operators: SearchRuleOperatorDefinition.unsupported([.containsPhrase, .matchesRegex, .doesNotMatchRegex]),
                valueEditor: .text,
                placeholder: L10n.string("search_rule.placeholder.script_text"),
                blockingMessageKey: "search_rule.unsupported.pending"
            )
        default:
            return SearchRuleFieldDefinition(
                operators: defaultTextOperators.map { SearchRuleOperatorDefinition(op: $0) },
                valueEditor: .text,
                placeholder: defaultPlaceholder
            )
        }
    }

    private var defaultTextOperators: [SearchRuleOperator] {
        [
            .contains,
            .containsPhrase,
            .beginsWith,
            .endsWith,
            .isExactly,
            .doesNotContain,
            .containsWords,
            .matchesPattern,
            .containsAnyOf,
            .beginsWithAnyOf,
            .endsWithAnyOf,
            .isAnyOf,
            .matchesRegex,
            .doesNotMatchRegex
        ]
    }

    private var defaultPlaceholder: String {
        switch self {
        case .name:
            return L10n.string("search_rule.placeholder.file_name")
        case .extensionName:
            return L10n.string("search_rule.placeholder.extension")
        case .nameWithoutExtension:
            return L10n.string("search_rule.placeholder.name")
        case .tag:
            return L10n.string("search_rule.placeholder.tag")
        case .textContent:
            return L10n.string("search_rule.placeholder.content")
        case .path:
            return L10n.string("search_rule.placeholder.path")
        case .folderNames:
            return L10n.string("search_rule.placeholder.folder_name")
        default:
            return L10n.string("search_rule.placeholder.value")
        }
    }
}

enum SearchRuleOperator: String, CaseIterable, Codable, Sendable {
    case contains = "contains"
    case containsPhrase = "contains phrase"
    case beginsWith = "begins with"
    case endsWith = "ends with"
    case isExactly = "is"
    case isNot = "is not"
    case doesNotContain = "doesn't contain"
    case containsWords = "contains words"
    case matchesPattern = "matches pattern"
    case containsAnyOf = "contains any of"
    case beginsWithAnyOf = "begins with any of"
    case endsWithAnyOf = "ends with any of"
    case isAnyOf = "is any of"
    case matchesRegex = "matches RegEx"
    case doesNotMatchRegex = "doesn't match RegEx"
    case isGreaterThan = "is greater than"
    case isLessThan = "is less than"
    case isBefore = "is before"
    case isAfter = "is after"
    case isOnOrBefore = "is on or before"
    case isOnOrAfter = "is on or after"
    case isWithinTheLast = "is within the last"
    case isToday = "is today"
    case isYesterday = "is yesterday"

    var localizedTitle: String {
        switch self {
        case .contains:
            return L10n.string("search_rule.operator.contains")
        case .containsPhrase:
            return L10n.string("search_rule.operator.contains_phrase")
        case .beginsWith:
            return L10n.string("search_rule.operator.begins_with")
        case .endsWith:
            return L10n.string("search_rule.operator.ends_with")
        case .isExactly:
            return L10n.string("search_rule.operator.is")
        case .isNot:
            return L10n.string("search_rule.operator.is_not")
        case .doesNotContain:
            return L10n.string("search_rule.operator.does_not_contain")
        case .containsWords:
            return L10n.string("search_rule.operator.contains_words")
        case .matchesPattern:
            return L10n.string("search_rule.operator.matches_pattern")
        case .containsAnyOf:
            return L10n.string("search_rule.operator.contains_any_of")
        case .beginsWithAnyOf:
            return L10n.string("search_rule.operator.begins_with_any_of")
        case .endsWithAnyOf:
            return L10n.string("search_rule.operator.ends_with_any_of")
        case .isAnyOf:
            return L10n.string("search_rule.operator.is_any_of")
        case .matchesRegex:
            return L10n.string("search_rule.operator.matches_regex")
        case .doesNotMatchRegex:
            return L10n.string("search_rule.operator.does_not_match_regex")
        case .isGreaterThan:
            return L10n.string("search_rule.operator.is_greater_than")
        case .isLessThan:
            return L10n.string("search_rule.operator.is_less_than")
        case .isBefore:
            return L10n.string("search_rule.operator.is_before")
        case .isAfter:
            return L10n.string("search_rule.operator.is_after")
        case .isOnOrBefore:
            return L10n.string("search_rule.operator.is_on_or_before")
        case .isOnOrAfter:
            return L10n.string("search_rule.operator.is_on_or_after")
        case .isWithinTheLast:
            return L10n.string("search_rule.operator.is_within_the_last")
        case .isToday:
            return L10n.string("search_rule.operator.is_today")
        case .isYesterday:
            return L10n.string("search_rule.operator.is_yesterday")
        }
    }
}

struct SearchRuleOperatorDefinition: Equatable, Sendable {
    let op: SearchRuleOperator
    let isSupported: Bool

    init(op: SearchRuleOperator, isSupported: Bool = true) {
        self.op = op
        self.isSupported = isSupported
    }

    var localizedTitle: String {
        op.localizedTitle
    }

    static func unsupported(_ operators: [SearchRuleOperator]) -> [SearchRuleOperatorDefinition] {
        operators.map { SearchRuleOperatorDefinition(op: $0, isSupported: false) }
    }
}

struct SearchRuleChoiceOption: Equatable, Sendable {
    let id: String
    let titleKey: String

    var localizedTitle: String {
        L10n.string(titleKey)
    }
}

enum SearchRuleRelativeDateUnit: String, CaseIterable, Codable, Sendable {
    case day
    case week
    case month

    var localizedTitle: String {
        switch self {
        case .day:
            return L10n.string("search_rule.relative.day")
        case .week:
            return L10n.string("search_rule.relative.week")
        case .month:
            return L10n.string("search_rule.relative.month")
        }
    }
}

struct SearchRuleRelativeDateValue: Equatable, Sendable {
    let amountText: String
    let unit: SearchRuleRelativeDateUnit?

    static func parse(_ rawValue: String) -> SearchRuleRelativeDateValue {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return SearchRuleRelativeDateValue(amountText: "", unit: nil)
        }

        if trimmed.contains("|") {
            let parts = trimmed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            return SearchRuleRelativeDateValue(
                amountText: parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                unit: parts.count > 1 ? SearchRuleRelativeDateUnit(rawValue: parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
            )
        }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if let first = tokens.first {
            let unit = tokens.count > 1 ? SearchRuleRelativeDateUnit(rawValue: tokens[1].lowercased()) : nil
            return SearchRuleRelativeDateValue(amountText: first, unit: unit)
        }

        return SearchRuleRelativeDateValue(amountText: trimmed, unit: nil)
    }

    static func encode(amountText: String, unit: SearchRuleRelativeDateUnit?) -> String {
        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAmount.isEmpty == false || unit != nil else {
            return ""
        }
        return trimmedAmount + "|" + (unit?.rawValue ?? "")
    }

    var positiveAmount: Int? {
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespacesAndNewlines)), amount > 0 else {
            return nil
        }
        return amount
    }
}

struct SearchRuleSelection: Codable, Equatable, Sendable {
    var field: SearchRuleField = .name
    var `operator`: SearchRuleOperator = .contains
    var value: String = ""
}

struct SearchRuleFieldDefinition: Sendable {
    let operators: [SearchRuleOperatorDefinition]
    let valueEditor: SearchRuleValueEditorKind
    let placeholder: String?
    let blockingMessageKey: String?
    private let editorOverrides: [SearchRuleOperator: SearchRuleValueEditorKind]
    private let placeholderOverrides: [SearchRuleOperator: String?]

    init(
        operators: [SearchRuleOperatorDefinition],
        valueEditor: SearchRuleValueEditorKind,
        placeholder: String?,
        blockingMessageKey: String? = nil,
        editorOverrides: [SearchRuleOperator: SearchRuleValueEditorKind] = [:],
        placeholderOverrides: [SearchRuleOperator: String?] = [:]
    ) {
        self.operators = operators
        self.valueEditor = valueEditor
        self.placeholder = placeholder
        self.blockingMessageKey = blockingMessageKey
        self.editorOverrides = editorOverrides
        self.placeholderOverrides = placeholderOverrides
    }

    var isSupported: Bool {
        operators.contains(where: \.isSupported)
    }

    func operatorDefinition(for searchOperator: SearchRuleOperator?) -> SearchRuleOperatorDefinition? {
        guard let searchOperator else {
            return operators.first
        }
        return operators.first(where: { $0.op == searchOperator })
    }

    func valueEditor(for searchOperator: SearchRuleOperator?) -> SearchRuleValueEditorKind {
        guard let searchOperator, let override = editorOverrides[searchOperator] else {
            return valueEditor
        }
        return override
    }

    func placeholder(for searchOperator: SearchRuleOperator?) -> String? {
        guard let searchOperator else {
            return placeholder
        }
        if let override = placeholderOverrides[searchOperator] {
            return override
        }
        return placeholder
    }

    func displayValue(for rawValue: String, operator searchOperator: SearchRuleOperator? = nil) -> String {
        switch valueEditor(for: searchOperator) {
        case .toggle(let falseLabel, let trueLabel):
            return SearchRuleSelection.booleanValue(from: rawValue) ? trueLabel : falseLabel
        case .choice(let options):
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return options.first(where: { $0.id == trimmed })?.localizedTitle ?? (trimmed.isEmpty ? "…" : trimmed)
        case .relativeDate:
            let parsed = SearchRuleRelativeDateValue.parse(rawValue)
            guard parsed.amountText.isEmpty == false else {
                return "…"
            }
            guard let unit = parsed.unit else {
                return parsed.amountText
            }
            return "\(parsed.amountText) \(unit.localizedTitle)"
        case .none:
            return ""
        case .text, .number, .date:
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "…" : trimmed
        }
    }

    func hidesValue(for searchOperator: SearchRuleOperator?) -> Bool {
        if case .none = valueEditor(for: searchOperator) {
            return true
        }
        return false
    }
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

extension SearchRuleSelection {
    static func booleanValue(from rawValue: String) -> Bool {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on", "include", "included":
            return true
        default:
            return false
        }
    }

    var summaryText: String {
        let fieldDefinition = field.definition
        let displayValue = fieldDefinition.displayValue(for: value, operator: `operator`)
        if fieldDefinition.hidesValue(for: `operator`) {
            return "\(field.localizedTitle) \(`operator`.localizedTitle)"
        }
        return "\(field.localizedTitle) \(`operator`.localizedTitle) \(displayValue)"
    }
}

enum SearchRuleValidationResult: Equatable, Sendable {
    case valid
    case unsupported(messageKey: String)
    case invalid(messageKey: String)

    var blockingMessageKey: String? {
        switch self {
        case .valid:
            return nil
        case .unsupported(let key), .invalid(let key):
            return key
        }
    }

    var blockingMessage: String? {
        blockingMessageKey.map(L10n.string)
    }
}

struct SearchRuleValidationSummary: Equatable, Sendable {
    let canSearch: Bool
    let firstBlockingMessage: String?
}

struct SearchRuleValidator: Sendable {
    func validate(_ selection: SearchRuleSelection) -> SearchRuleValidationResult {
        let definition = selection.field.definition
        let unsupportedKey = definition.blockingMessageKey ?? "search_rule.unsupported.pending"

        guard let operatorDefinition = definition.operatorDefinition(for: selection.operator) else {
            return .unsupported(messageKey: unsupportedKey)
        }

        if definition.isSupported == false || operatorDefinition.isSupported == false {
            return .unsupported(messageKey: unsupportedKey)
        }

        switch definition.valueEditor(for: selection.operator) {
        case .relativeDate(let units):
            let value = SearchRuleRelativeDateValue.parse(selection.value)
            guard value.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return .invalid(messageKey: "search_rule.validation.relative_date_amount_required")
            }
            guard value.positiveAmount != nil else {
                return .invalid(messageKey: "search_rule.validation.relative_date_amount_required")
            }
            guard let unit = value.unit, units.contains(unit) else {
                return .invalid(messageKey: "search_rule.validation.relative_date_unit_required")
            }
        case .date:
            guard SearchRuleDateParser.parse(selection.value) != nil else {
                return .invalid(messageKey: "search_rule.validation.date_required")
            }
        case .choice(let options):
            let trimmedValue = selection.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard options.contains(where: { $0.id == trimmedValue }) else {
                return .invalid(messageKey: "search_rule.validation.selection_required")
            }
            if selection.field == .kind,
               selection.operator == .isNot,
               trimmedValue == SearchRuleChoiceOption.kindAnyID {
                return .invalid(messageKey: "search_rule.validation.kind_not_any")
            }
        case .none:
            break
        case .text, .number, .toggle:
            break
        }

        return .valid
    }
}

enum SearchRuleDateParser {
    static func parse(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return ISO8601DateFormatter().date(from: trimmed)
    }
}

private extension SearchRuleChoiceOption {
    static let kindAnyID = "kind.any"

    static let kindOptions: [SearchRuleChoiceOption] = [
        .init(id: "kind.any", titleKey: "search_rule.kind.any"),
        .init(id: "kind.alias_or_symlink", titleKey: "search_rule.kind.alias_or_symlink"),
        .init(id: "kind.applescript", titleKey: "search_rule.kind.applescript"),
        .init(id: "kind.application", titleKey: "search_rule.kind.application"),
        .init(id: "kind.archive", titleKey: "search_rule.kind.archive"),
        .init(id: "kind.audio", titleKey: "search_rule.kind.audio"),
        .init(id: "kind.directory", titleKey: "search_rule.kind.directory"),
        .init(id: "kind.disk_image", titleKey: "search_rule.kind.disk_image"),
        .init(id: "kind.ebook", titleKey: "search_rule.kind.ebook"),
        .init(id: "kind.file", titleKey: "search_rule.kind.file"),
        .init(id: "kind.finder_alias", titleKey: "search_rule.kind.finder_alias"),
        .init(id: "kind.folder", titleKey: "search_rule.kind.folder"),
        .init(id: "kind.font", titleKey: "search_rule.kind.font"),
        .init(id: "kind.image", titleKey: "search_rule.kind.image"),
        .init(id: "kind.package", titleKey: "search_rule.kind.package"),
        .init(id: "kind.pdf", titleKey: "search_rule.kind.pdf"),
        .init(id: "kind.plain_text", titleKey: "search_rule.kind.plain_text"),
        .init(id: "kind.presentation", titleKey: "search_rule.kind.presentation"),
        .init(id: "kind.spreadsheet", titleKey: "search_rule.kind.spreadsheet"),
        .init(id: "kind.symlink", titleKey: "search_rule.kind.symlink"),
        .init(id: "kind.text", titleKey: "search_rule.kind.text"),
        .init(id: "kind.unix_executable", titleKey: "search_rule.kind.unix_executable"),
        .init(id: "kind.video", titleKey: "search_rule.kind.video"),
        .init(id: "kind.word_pages", titleKey: "search_rule.kind.word_pages")
    ]
}

#if DEBUG
extension SearchRuleValueEditorKind {
    var debugStyle: String {
        switch self {
        case .text:
            return "text"
        case .number:
            return "number"
        case .date:
            return "date"
        case .relativeDate:
            return "relativeDate"
        case .none:
            return "none"
        case .toggle:
            return "toggle"
        case .choice:
            return "choice"
        }
    }

    var debugOptionIDs: [String] {
        switch self {
        case .choice(let options):
            return options.map(\.id)
        default:
            return []
        }
    }
}
#endif
