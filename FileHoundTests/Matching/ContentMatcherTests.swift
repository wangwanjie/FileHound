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
        // 只忽略变音符号时，不带变音的字母也能匹配带变音的写法，不能用来按字节预筛
        XCTAssertEqual(ContentMatcher.longestFoldInvariantRun(of: "Report-2026", compareOptions: [.diacriticInsensitive]), "-2026")
        XCTAssertNil(ContentMatcher.longestFoldInvariantRun(of: "שלום", compareOptions: [.diacriticInsensitive]))
    }

    private func matches(
        _ searchOperator: SearchRuleOperator,
        _ value: String,
        in data: Data,
        options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    ) throws -> Bool {
        try ContentMatcher().matches(
            data: data,
            rule: SearchRuleSelection(field: .textContent, operator: searchOperator, value: value),
            compareOptions: options,
            caseSensitive: options.contains(.caseInsensitive) == false
        )
    }

    func testCaseSensitiveDiacriticInsensitiveSearchMatchesAccentedContent() throws {
        let caseSensitiveOnly: String.CompareOptions = [.diacriticInsensitive]

        XCTAssertTrue(try matches(.contains, "Resume", in: Data("My Résumé 2026".utf8), options: caseSensitiveOnly))
        XCTAssertFalse(try matches(.contains, "resume", in: Data("My Résumé 2026".utf8), options: caseSensitiveOnly))
        XCTAssertTrue(try matches(.contains, "שלום", in: Data("אמר שָׁלוֹם לכולם".utf8), options: caseSensitiveOnly))
        // 二进制内容中的 UTF-16 文字同样按折叠后的形式查找
        var binary = Data([0, 1, 0])
        binary.append("Resume".data(using: .utf16LittleEndian)!)
        XCTAssertTrue(try matches(.contains, "Résumé", in: binary, options: caseSensitiveOnly))
    }

    func testLatin1BytesOnlyMatchContentThatIsNotUTF8() throws {
        // “退”（U+9000）的 UTF-8 编码以 0xE9 开头，与 “é” 的 Latin-1 编码相同，不能因此误报
        XCTAssertFalse(try matches(.contains, "é", in: Data("撤退了".utf8), options: []))
        // 真正的 Latin-1 文本（不是合法 UTF-8）仍能按 Latin-1 找到
        let latin1 = try XCTUnwrap("café crème".data(using: .isoLatin1))
        XCTAssertTrue(try matches(.contains, "é", in: latin1, options: []))
        XCTAssertTrue(try matches(.contains, "CRÈME", in: latin1))
    }

    func testNonContainsOperatorsDecodeOnceAndHandleBinaryAndInvalidRegex() throws {
        let text = Data("Hello World".utf8)
        XCTAssertTrue(try matches(.beginsWith, "hello", in: text))
        XCTAssertTrue(try matches(.endsWith, "world", in: text))
        XCTAssertTrue(try matches(.matchesRegex, "^hello\\s+w", in: text))
        XCTAssertTrue(try matches(.matchesPattern, "hello*", in: text))
        XCTAssertTrue(try matches(.beginsWith, "hello", in: try XCTUnwrap("Hello".data(using: .utf16))))

        // “是任一”要求整个内容与某一项相同，而不是包含
        XCTAssertTrue(try matches(.isAnyOf, "abc, xyz", in: Data("ABC".utf8)))
        XCTAssertFalse(try matches(.isAnyOf, "abc", in: Data("abcdef".utf8)))

        // 二进制文件没有可比较的文字：肯定类不命中，否定类视为满足
        let binary = Data([0x00, 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00])
        XCTAssertFalse(try matches(.matchesRegex, "Hello", in: binary))
        XCTAssertTrue(try matches(.doesNotMatchRegex, "Hello", in: binary))

        // 非法正则无法判定，“不匹配”也不能命中所有文件
        XCTAssertFalse(try matches(.matchesRegex, "(", in: text))
        XCTAssertFalse(try matches(.doesNotMatchRegex, "(", in: text))

        // 调用方预先编译的正则直接使用
        let regex = try NSRegularExpression(pattern: "W.RLD", options: [.caseInsensitive])
        XCTAssertTrue(try ContentMatcher().matches(
            data: text,
            rule: SearchRuleSelection(field: .textContent, operator: .matchesRegex, value: "unused"),
            compareOptions: [.caseInsensitive],
            caseSensitive: false,
            regex: regex
        ))
    }

    func testOversizedContentIsNotDecodedForNonContainsOperators() throws {
        var large = Data(count: ContentMatcher.maximumDecodedContentSize + 1)
        large.replaceSubrange(0..<5, with: Data("hello".utf8))
        XCTAssertFalse(try matches(.beginsWith, "hello", in: large))
        // “包含”类按字节查找，不受大小限制
        XCTAssertTrue(try matches(.contains, "hello", in: large))
    }
}
