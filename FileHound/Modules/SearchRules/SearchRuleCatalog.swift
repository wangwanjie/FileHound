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
                operators: [.isExactly, .isBefore, .isAfter],
                valueEditor: .date,
                placeholder: L10n.string("search_rule.placeholder.date")
            )
        case .fileSize, .limitFolderDepth, .limitAmount:
            return SearchRuleFieldDefinition(
                operators: [.isExactly, .isGreaterThan, .isLessThan],
                valueEditor: .number,
                placeholder: L10n.string("search_rule.placeholder.value")
            )
        case .caseSensitive, .diacriticsSensitive:
            return SearchRuleFieldDefinition(
                operators: [.isExactly],
                valueEditor: .toggle(
                    falseLabel: L10n.string("search_rule.toggle.off"),
                    trueLabel: L10n.string("search_rule.toggle.on")
                ),
                placeholder: nil
            )
        case .invisibleItems, .packageContents, .trashedContents:
            return SearchRuleFieldDefinition(
                operators: [.isExactly],
                valueEditor: .toggle(
                    falseLabel: L10n.string("search_rule.toggle.exclude"),
                    trueLabel: L10n.string("search_rule.toggle.include")
                ),
                placeholder: nil
            )
        case .script:
            return SearchRuleFieldDefinition(
                operators: [.containsPhrase, .matchesRegex, .doesNotMatchRegex],
                valueEditor: .text,
                placeholder: L10n.string("search_rule.placeholder.script_text")
            )
        default:
            return SearchRuleFieldDefinition(
                operators: [
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
                ],
                valueEditor: .text,
                placeholder: defaultPlaceholder
            )
        }
    }

    private var defaultPlaceholder: String {
        switch self {
        case .name:
            return L10n.string("search_rule.placeholder.file_name")
        case .extensionName:
            return L10n.string("search_rule.placeholder.extension")
        case .nameWithoutExtension:
            return L10n.string("search_rule.placeholder.name")
        case .kind:
            return L10n.string("search_rule.placeholder.kind")
        case .tag:
            return L10n.string("search_rule.placeholder.tag")
        case .comments:
            return L10n.string("search_rule.placeholder.comment")
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
        }
    }
}

struct SearchRuleSelection: Codable, Equatable, Sendable {
    var field: SearchRuleField = .name
    var `operator`: SearchRuleOperator = .contains
    var value: String = ".lookin"
}

struct SearchRuleFieldDefinition: Sendable {
    let operators: [SearchRuleOperator]
    let valueEditor: SearchRuleValueEditorKind
    let placeholder: String?

    func displayValue(for rawValue: String) -> String {
        switch valueEditor {
        case .toggle(let falseLabel, let trueLabel):
            return SearchRuleSelection.booleanValue(from: rawValue) ? trueLabel : falseLabel
        case .text, .number, .date:
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "…" : trimmed
        }
    }
}

enum SearchRuleValueEditorKind: Equatable, Sendable {
    case text
    case number
    case date
    case toggle(falseLabel: String, trueLabel: String)
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
        "\(field.localizedTitle) \(`operator`.localizedTitle) \(field.definition.displayValue(for: value))"
    }
}
