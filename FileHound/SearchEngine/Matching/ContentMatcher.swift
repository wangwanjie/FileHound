import Darwin
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

        // “包含”类条件逐词在字节层面判定，不必把整个文件解码成字符串再做宽松比较
        let content = LazyTextContent(data: data)
        switch rule.operator {
        case .contains, .containsPhrase:
            return containsText(trimmedValue, in: content, compareOptions: compareOptions)
        case .doesNotContain:
            return containsText(trimmedValue, in: content, compareOptions: compareOptions) == false
        case .containsWords:
            return splitTerms(from: trimmedValue).allSatisfy {
                containsText($0, in: content, compareOptions: compareOptions)
            }
        case .containsAnyOf:
            return splitTerms(from: trimmedValue).contains {
                containsText($0, in: content, compareOptions: compareOptions)
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

    /// 判定文件内容是否包含 needle，结果与把内容解码后用 range(of:options:) 查找一致，但大多数文件只需按字节查找：
    /// 先找原样编码的 needle；再用其中不受大小写、变音符号影响的连续字符预筛，宽松比较下能命中的内容必然逐字节含有它；
    /// 都无法定论时才按内容的实际形态比较
    private func containsText(_ needle: String, in content: LazyTextContent, compareOptions: String.CompareOptions) -> Bool {
        let data = content.data
        if fastContains(data: data, needle: needle) {
            return true
        }

        if let invariantRun = Self.longestFoldInvariantRun(of: needle, compareOptions: compareOptions) {
            // 整个 needle 都不受折叠影响时，按字节查找已经是最终结果
            if invariantRun == needle || fastContains(data: data, needle: invariantRun) == false {
                return false
            }
        }

        guard compareOptions.isSubset(of: [.caseInsensitive, .diacriticInsensitive]) else {
            return decodedCandidates(from: data).contains { $0.range(of: needle, options: compareOptions) != nil }
        }

        let caseInsensitive = compareOptions.contains(.caseInsensitive)
        var folded = needle
        if compareOptions.contains(.diacriticInsensitive) {
            folded = folded.folding(options: .diacriticInsensitive, locale: nil)
        }
        if caseInsensitive {
            folded = folded.lowercased()
        }

        switch content.form {
        case .text(let string):
            return string.range(of: needle, options: compareOptions) != nil
        case .ascii:
            // 纯 ASCII 内容里没有变音符号，折叠后的 needle 仍是 ASCII 时按字节忽略大小写查找即可
            guard folded.utf8.allSatisfy({ $0 < 0x80 }) else {
                return String(decoding: data, as: UTF8.self).range(of: needle, options: compareOptions) != nil
            }
            return Self.containsBytes(Array(folded.utf8), in: data, asciiCaseInsensitive: caseInsensitive)
        case .binary:
            // 二进制文件中的文字只按常见编码逐字节查找（ASCII 字母忽略大小写），不再整体解码成字符串
            let encodings: [String.Encoding] = [.utf8, .utf16LittleEndian, .utf16BigEndian, .isoLatin1]
            return encodings.contains { encoding in
                guard let encoded = folded.data(using: encoding) else {
                    return false
                }
                return Self.containsBytes(Array(encoded), in: data, asciiCaseInsensitive: caseInsensitive)
            }
        }
    }

    /// 不受当前比较选项影响的字符：既没有大小写和变音符号变体，也没有其他 Unicode 组合形式，
    /// 宽松比较下能匹配它的只有它自身的编码
    private static func isFoldInvariant(_ character: Character, compareOptions: String.CompareOptions) -> Bool {
        let value = String(character)
        if compareOptions.contains(.caseInsensitive), value.lowercased() != value || value.uppercased() != value {
            return false
        }
        if compareOptions.contains(.diacriticInsensitive), value.folding(options: .diacriticInsensitive, locale: nil) != value {
            return false
        }
        return value.decomposedStringWithCanonicalMapping == value && value.precomposedStringWithCanonicalMapping == value
    }

    static func longestFoldInvariantRun(of needle: String, compareOptions: String.CompareOptions) -> String? {
        var longest = ""
        var current = ""
        for character in needle {
            if isFoldInvariant(character, compareOptions: compareOptions) {
                current.append(character)
                if current.utf8.count > longest.utf8.count {
                    longest = current
                }
            } else {
                current = ""
            }
        }
        return longest.isEmpty ? nil : longest
    }

    /// 分块查找，忽略大小写时把每块的 ASCII 大写字母转成小写后再找，避免为大文件复制整份内容
    private static func containsBytes(_ needle: [UInt8], in data: Data, asciiCaseInsensitive: Bool) -> Bool {
        guard needle.isEmpty == false else {
            return true
        }
        guard asciiCaseInsensitive else {
            return needle.withUnsafeBytes { bytesContain($0, in: data) }
        }

        let loweredNeedle = needle.map(asciiLowercased)
        let chunkSize = max(1 << 20, needle.count * 2)
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        return data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Bool in
            guard source.count >= needle.count else {
                return false
            }
            var start = 0
            while start + needle.count <= source.count {
                let length = min(chunkSize, source.count - start)
                let found = chunk.withUnsafeMutableBufferPointer { buffer -> Bool in
                    for index in 0..<length {
                        buffer[index] = asciiLowercased(source[start + index])
                    }
                    return loweredNeedle.withUnsafeBytes { needleBytes in
                        memmem(buffer.baseAddress!, length, needleBytes.baseAddress!, needleBytes.count) != nil
                    }
                }
                if found {
                    return true
                }
                // 相邻块重叠 needle 长度减一，跨块的匹配不会漏掉
                start += length - (needle.count - 1)
                if start + needle.count > source.count || length < chunkSize {
                    break
                }
            }
            return false
        }
    }

    @inline(__always)
    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        byte &- 0x41 < 26 ? byte | 0x20 : byte
    }

    private func fastContains(data: Data, needle: String) -> Bool {
        encodedNeedles(for: needle).contains { encoded in
            encoded.withUnsafeBytes { Self.bytesContain($0, in: data) }
        }
    }

    /// 用 memmem 查找：Data.range(of:) 在未优化的构建里每字节都要走泛型代码，大文件上慢几十倍
    private static func bytesContain(_ needle: UnsafeRawBufferPointer, in data: Data) -> Bool {
        guard let needleBase = needle.baseAddress, needle.isEmpty == false else {
            return true
        }
        return data.withUnsafeBytes { source in
            guard let sourceBase = source.baseAddress, source.count >= needle.count else {
                return false
            }
            return memmem(sourceBase, source.count, needleBase, needle.count) != nil
        }
    }

    private func encodedNeedles(for needle: String) -> [Data] {
        // 包含 isoLatin1：慢速路径也会按它解码，按字节找到即可直接确认
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32LittleEndian,
            .utf32BigEndian,
            .isoLatin1
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
        case .isNot:
            return candidate.compare(trimmedValue, options: compareOptions) != .orderedSame
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
        case .isGreaterThan, .isLessThan, .isBefore, .isAfter, .isOnOrBefore, .isOnOrAfter, .isWithinTheLast, .isToday, .isYesterday:
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

/// 文件内容的形态，同一文件判定多个词时只识别一次，且只在字节查找无法定论时才识别
private final class LazyTextContent {
    enum Form {
        /// 不含 NUL 的纯 ASCII 文本
        case ascii
        /// 能确定编码的文本（带 BOM，或不含 NUL 的 UTF-8 / Latin-1）
        case text(String)
        /// 含 NUL 且无 BOM，按二进制处理
        case binary
    }

    let data: Data
    private var cachedForm: Form?

    init(data: Data) {
        self.data = data
    }

    var form: Form {
        if let cachedForm {
            return cachedForm
        }
        let form = Self.detectForm(of: data)
        cachedForm = form
        return form
    }

    private static func detectForm(of data: Data) -> Form {
        let prefix = [UInt8](data.prefix(4))
        let bomEncoding: String.Encoding?
        if prefix.starts(with: [0xFF, 0xFE, 0x00, 0x00]) || prefix.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            bomEncoding = .utf32
        } else if prefix.starts(with: [0xFF, 0xFE]) || prefix.starts(with: [0xFE, 0xFF]) {
            bomEncoding = .utf16
        } else {
            bomEncoding = nil
        }
        if let bomEncoding, let string = String(data: data, encoding: bomEncoding) {
            return .text(string)
        }

        let (hasNul, isASCII) = data.withUnsafeBytes { bytes -> (Bool, Bool) in
            guard let base = bytes.baseAddress, bytes.isEmpty == false else {
                return (false, true)
            }
            var combined: UInt8 = 0
            for byte in bytes {
                combined |= byte
            }
            return (memchr(base, 0, bytes.count) != nil, combined < 0x80)
        }
        if hasNul {
            return .binary
        }
        if isASCII {
            return .ascii
        }
        if let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return .text(string)
        }
        return .binary
    }
}
