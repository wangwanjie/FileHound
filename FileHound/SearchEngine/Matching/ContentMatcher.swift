import Foundation

struct ContentMatcher: Sendable {
    func matches(data: Data, query: QueryRule) throws -> Bool {
        switch query {
        case .contentContains(let needle):
            return try matches(
                data: data,
                rule: SearchRuleSelection(field: .textContent, operator: .contains, value: needle),
                compareOptions: [.caseInsensitive, .diacriticInsensitive],
                caseSensitive: false
            )
        case .contentMatchesRegex(let pattern):
            return try matches(
                data: data,
                rule: SearchRuleSelection(field: .textContent, operator: .matchesRegex, value: pattern),
                compareOptions: [.caseInsensitive, .diacriticInsensitive],
                caseSensitive: false
            )
        default:
            return false
        }
    }

    func matches(
        data: Data,
        rule: SearchRuleSelection,
        compareOptions: String.CompareOptions,
        caseSensitive: Bool
    ) throws -> Bool {
        let trimmedValue = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false else {
            return true
        }

        switch rule.operator {
        case .contains, .containsPhrase:
            if fastContains(data: data, needle: trimmedValue) {
                return true
            }
        case .doesNotContain:
            if fastContains(data: data, needle: trimmedValue) {
                return false
            }
        case .containsWords:
            let terms = splitTerms(from: trimmedValue)
            if terms.isEmpty == false, terms.allSatisfy({ fastContains(data: data, needle: $0) }) {
                return true
            }
        case .containsAnyOf:
            let terms = splitTerms(from: trimmedValue)
            if terms.contains(where: { fastContains(data: data, needle: $0) }) {
                return true
            }
        case .isAnyOf:
            let terms = splitTerms(from: trimmedValue)
            if terms.contains(where: { fastContains(data: data, needle: $0) }) {
                return true
            }
        default:
            break
        }

        let candidates = decodedCandidates(from: data)
        guard candidates.isEmpty == false else {
            return false
        }

        return candidates.contains {
            matches(
                candidate: $0,
                rule: rule,
                compareOptions: compareOptions,
                caseSensitive: caseSensitive
            )
        }
    }

    private func fastContains(data: Data, needle: String) -> Bool {
        encodedNeedles(for: needle).contains { data.range(of: $0) != nil }
    }

    private func encodedNeedles(for needle: String) -> [Data] {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32LittleEndian,
            .utf32BigEndian
        ]
        var seen = Set<Data>()
        var encodedValues: [Data] = []

        for encoding in encodings {
            guard let data = needle.data(using: encoding), seen.insert(data).inserted else {
                continue
            }
            encodedValues.append(data)
        }

        return encodedValues
    }

    private func decodedCandidates(from data: Data) -> [String] {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32,
            .utf32LittleEndian,
            .utf32BigEndian,
            .isoLatin1
        ]

        var candidates: [String] = []
        var seen = Set<String>()

        for encoding in encodings {
            guard let string = String(data: data, encoding: encoding),
                  string.isEmpty == false,
                  seen.insert(string).inserted else {
                continue
            }
            candidates.append(string)
        }

        if candidates.isEmpty {
            let fallback = String(decoding: data, as: UTF8.self)
            if fallback.isEmpty == false {
                candidates.append(fallback)
            }
        }

        return candidates
    }

    private func matches(
        candidate: String,
        rule: SearchRuleSelection,
        compareOptions: String.CompareOptions,
        caseSensitive: Bool
    ) -> Bool {
        let trimmedValue = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)

        switch rule.operator {
        case .contains, .containsPhrase:
            return candidate.range(of: trimmedValue, options: compareOptions) != nil
        case .beginsWith:
            return candidate.range(of: trimmedValue, options: compareOptions.union(.anchored)) != nil
        case .endsWith:
            return candidate.range(of: trimmedValue, options: compareOptions.union(.backwards))?.upperBound == candidate.endIndex
        case .isExactly:
            return candidate.compare(trimmedValue, options: compareOptions) == .orderedSame
        case .doesNotContain:
            return candidate.range(of: trimmedValue, options: compareOptions) == nil
        case .containsWords:
            return splitTerms(from: trimmedValue).allSatisfy {
                candidate.range(of: $0, options: compareOptions) != nil
            }
        case .matchesPattern:
            return matchRegex(candidate, pattern: wildcardPattern(from: trimmedValue), caseSensitive: caseSensitive)
        case .containsAnyOf:
            return splitTerms(from: trimmedValue).contains {
                candidate.range(of: $0, options: compareOptions) != nil
            }
        case .beginsWithAnyOf:
            return splitTerms(from: trimmedValue).contains {
                candidate.range(of: $0, options: compareOptions.union(.anchored)) != nil
            }
        case .endsWithAnyOf:
            return splitTerms(from: trimmedValue).contains {
                candidate.range(of: $0, options: compareOptions.union(.backwards))?.upperBound == candidate.endIndex
            }
        case .isAnyOf:
            return splitTerms(from: trimmedValue).contains {
                candidate.compare($0, options: compareOptions) == .orderedSame
            }
        case .matchesRegex:
            return matchRegex(candidate, pattern: trimmedValue, caseSensitive: caseSensitive)
        case .doesNotMatchRegex:
            return matchRegex(candidate, pattern: trimmedValue, caseSensitive: caseSensitive) == false
        case .isGreaterThan, .isLessThan, .isBefore, .isAfter:
            return false
        }
    }

    private func splitTerms(from value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { $0.isEmpty == false }
    }

    private func wildcardPattern(from value: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: value)
        return "^" + escaped
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
    }

    private func matchRegex(_ candidate: String, pattern: String, caseSensitive: Bool) -> Bool {
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return false
        }

        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        return regex.firstMatch(in: candidate, options: [], range: range) != nil
    }
}
