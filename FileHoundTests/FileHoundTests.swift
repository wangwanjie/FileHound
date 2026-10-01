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
    func everyFieldIsSupported() {
        for field in SearchRuleField.allCases {
            #expect(field.definition.isSupported, "\(field) should be searchable")
            #expect(field.definition.blockingMessageKey == nil)
        }
        #expect(SearchRuleField.script.definition.operators.map(\.op) == [.containsPhrase, .matchesRegex, .doesNotMatchRegex])
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
    func commentsAndScriptRulesValidate() {
        let validator = SearchRuleValidator()

        #expect(validator.validate(SearchRuleSelection(field: .comments, operator: .containsPhrase, value: "note")) == .valid)
        #expect(validator.validate(SearchRuleSelection(field: .script, operator: .matchesRegex, value: "tell .*")) == .valid)
    }
}
