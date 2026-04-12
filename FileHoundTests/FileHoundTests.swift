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
