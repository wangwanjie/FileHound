import Foundation
import XCTest
@testable import FileHound

final class ContentMatcherTests: XCTestCase {
    func testMatchesPlainTextAndRegex() throws {
        let matcher = ContentMatcher()

        XCTAssertTrue(try matcher.matches(data: Data("hello needle".utf8), query: .contentContains("needle")))
        XCTAssertTrue(try matcher.matches(data: Data("error-42".utf8), query: .contentMatchesRegex("error-[0-9]+")))
    }

    func testMatchesUTF16AndStructuredTextOperators() throws {
        let matcher = ContentMatcher()
        let utf16Data = "icon size 32x32 in manifest".data(using: .utf16LittleEndian)!

        XCTAssertTrue(try matcher.matches(
            data: utf16Data,
            rule: SearchRuleSelection(field: .textContent, operator: .contains, value: "32x32"),
            compareOptions: [.caseInsensitive, .diacriticInsensitive],
            caseSensitive: false
        ))
        XCTAssertTrue(try matcher.matches(
            data: utf16Data,
            rule: SearchRuleSelection(field: .textContent, operator: .containsAnyOf, value: "16x16,32x32"),
            compareOptions: [.caseInsensitive, .diacriticInsensitive],
            caseSensitive: false
        ))
        XCTAssertFalse(try matcher.matches(
            data: utf16Data,
            rule: SearchRuleSelection(field: .textContent, operator: .doesNotContain, value: "32x32"),
            compareOptions: [.caseInsensitive, .diacriticInsensitive],
            caseSensitive: false
        ))
    }
}
