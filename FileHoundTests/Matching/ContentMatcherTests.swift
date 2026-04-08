import Foundation
import XCTest
@testable import FileHound

final class ContentMatcherTests: XCTestCase {
    func testMatchesPlainTextAndRegex() throws {
        let matcher = ContentMatcher()

        XCTAssertTrue(try matcher.matches(data: Data("hello needle".utf8), query: .contentContains("needle")))
        XCTAssertTrue(try matcher.matches(data: Data("error-42".utf8), query: .contentMatchesRegex("error-[0-9]+")))
    }
}
