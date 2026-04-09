import Foundation

enum SearchRuleField: String, CaseIterable, Sendable {
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
}

enum SearchRuleOperator: String, CaseIterable, Sendable {
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
}

struct SearchRuleSelection: Equatable, Sendable {
    var field: SearchRuleField = .name
    var `operator`: SearchRuleOperator = .contains
    var value: String = ".lookin"
}
