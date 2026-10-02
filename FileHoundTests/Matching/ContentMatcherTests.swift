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

    func testContainsSearchHandlesCaseDiacriticsAndEncodingsWithoutFullDecoding() throws {
        let insensitive: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        func contains(_ needle: String, in data: Data, options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]) throws -> Bool {
            try ContentMatcher().matches(
                data: data,
                rule: SearchRuleSelection(field: .textContent, operator: .contains, value: needle),
                compareOptions: options,
                caseSensitive: options.contains(.caseInsensitive) == false
            )
        }

        // 不含字母的片段只需按字节查找
        XCTAssertTrue(try contains("05-屏幕截图", in: Data("//  05-屏幕截图\n".utf8)))
        XCTAssertTrue(try contains("05-屏幕截图", in: "05-屏幕截图".data(using: .utf16LittleEndian)!))
        XCTAssertFalse(try contains("05-屏幕截图", in: Data("05 张屏幕截图".utf8)))

        // 纯 ASCII 文本：忽略大小写，带变音符号的 needle 也能命中
        XCTAssertTrue(try contains("report", in: Data("Monthly REPORT".utf8)))
        XCTAssertTrue(try contains("Résumé", in: Data("my resume".utf8)))
        XCTAssertFalse(try contains("Résumé", in: Data("my resume".utf8), options: [.caseInsensitive]))
        XCTAssertFalse(try contains("report", in: Data("Monthly REPORT".utf8), options: [.diacriticInsensitive]))

        // 非 ASCII 文本按解码后的字符串比较
        XCTAssertTrue(try contains("resume", in: Data("Mon RÉSUMÉ 测试".utf8)))
        XCTAssertTrue(try contains("Straße", in: Data("Hauptstraße 测试".utf8)))

        // 预筛：不受折叠影响的部分不存在时直接判定不命中
        XCTAssertTrue(try contains("05-report", in: Data("x 05-REPORT".utf8)))
        XCTAssertFalse(try contains("05-report", in: Data("x 06-REPORT".utf8)))

        // 二进制内容（含 NUL）中的 UTF-8 与无 BOM 的 UTF-16 文字
        var binary = Data([0, 1, 2, 0xFF, 0])
        binary.append(Data("Hello World".utf8))
        binary.append(Data([0, 0]))
        binary.append("Second Value".data(using: .utf16LittleEndian)!)
        XCTAssertTrue(try contains("hello world", in: binary))
        XCTAssertTrue(try contains("second value", in: binary))
        XCTAssertFalse(try contains("third value", in: binary))

        // 跨越分块边界的匹配
        var large = Data(repeating: 0x61, count: (1 << 20) - 3)
        large.append(Data("NEEDLE".utf8))
        large.append(Data([0]))
        XCTAssertTrue(try contains("needle", in: large))
        XCTAssertTrue(try contains("aNeedle", in: large))

        XCTAssertEqual(ContentMatcher.longestFoldInvariantRun(of: "05-屏幕截图", compareOptions: insensitive), "05-屏幕截图")
        XCTAssertEqual(ContentMatcher.longestFoldInvariantRun(of: "Report-2026", compareOptions: insensitive), "-2026")
        XCTAssertNil(ContentMatcher.longestFoldInvariantRun(of: "report", compareOptions: insensitive))
        XCTAssertEqual(ContentMatcher.longestFoldInvariantRun(of: "report", compareOptions: []), "report")
    }
}
