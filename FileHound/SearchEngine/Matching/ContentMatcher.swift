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

    /// 非“包含”类运算符需要把整个文件解码成字符串再比较，超过这个大小的文件不再解码（视为不匹配）：
    /// 多个线程同时解码几百 MB 的文件会占用大量内存，而这类运算符（正则、开头是、完全是等）对超大文件几乎没有意义
    static let maximumDecodedContentSize = 64 << 20

    /// regex 为调用方预先编译好的正则（正则、通配符运算符使用），为 nil 时按规则值临时编译
    func matches(
        data: Data,
        rule: SearchRuleSelection,
        compareOptions: String.CompareOptions,
        caseSensitive: Bool,
        regex: NSRegularExpression? = nil
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
        default:
            break
        }

        guard data.count <= Self.maximumDecodedContentSize else {
            return false
        }

        // 只解码一次：编码由 LazyTextContent 识别，不再按多种编码各解码出一份完整副本
        let text: String
        switch content.form {
        case .binary:
            // 二进制文件没有可比较的文字：肯定类运算符不命中，否定类运算符视为满足（与“不包含”一致）
            return Self.isNegativeOperator(rule.operator)
        case .ascii:
            text = String(decoding: data, as: UTF8.self)
        case .utf8(let string), .unicodeWithBOM(let string), .latin1(let string):
            text = string
        }

        let compiledRegex: NSRegularExpression?
        switch rule.operator {
        case .matchesRegex, .doesNotMatchRegex, .matchesPattern:
            compiledRegex = regex ?? Self.compileRegex(for: rule.operator, value: trimmedValue, caseSensitive: caseSensitive)
        default:
            compiledRegex = nil
        }

        return matches(
            candidate: text,
            value: trimmedValue,
            operator: rule.operator,
            compareOptions: compareOptions,
            regex: compiledRegex
        )
    }

    /// 编译正则 / 通配符运算符使用的正则；非法正则返回 nil
    static func compileRegex(for searchOperator: SearchRuleOperator, value: String, caseSensitive: Bool) -> NSRegularExpression? {
        let pattern: String
        switch searchOperator {
        case .matchesPattern:
            pattern = wildcardPattern(from: value)
        case .matchesRegex, .doesNotMatchRegex:
            pattern = value
        default:
            return nil
        }
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        return try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// 把 “*”“?” 通配符转换为整串匹配的正则
    static func wildcardPattern(from value: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: value)
        return "^" + escaped
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".") + "$"
    }

    /// 按字节查找即可判定、不需要整份解码的“包含”类运算符，不受 maximumDecodedContentSize 限制
    static func isContainsOperator(_ searchOperator: SearchRuleOperator) -> Bool {
        switch searchOperator {
        case .contains, .containsPhrase, .doesNotContain, .containsWords, .containsAnyOf:
            return true
        default:
            return false
        }
    }

    private static func isNegativeOperator(_ searchOperator: SearchRuleOperator) -> Bool {
        switch searchOperator {
        case .isNot, .doesNotContain, .doesNotMatchRegex:
            return true
        default:
            return false
        }
    }

    /// 判定文件内容是否包含 needle，结果与把内容解码后用 range(of:options:) 查找一致，但大多数文件只需按字节查找：
    /// 先找原样编码的 needle；再用其中不受大小写、变音符号影响的连续字符预筛，宽松比较下能命中的内容必然逐字节含有它；
    /// 都无法定论时才按内容的实际形态比较
    private func containsText(_ needle: String, in content: LazyTextContent, compareOptions: String.CompareOptions) -> Bool {
        if containsEncoded(needle, in: content) {
            return true
        }

        if let invariantRun = Self.longestFoldInvariantRun(of: needle, compareOptions: compareOptions) {
            // 整个 needle 都不受折叠影响时，按字节查找已经是最终结果
            if invariantRun == needle || containsEncoded(invariantRun, in: content) == false {
                return false
            }
        }

        let data = content.data
        guard compareOptions.isSubset(of: [.caseInsensitive, .diacriticInsensitive]) else {
            return content.decodedText.map { $0.range(of: needle, options: compareOptions) != nil } ?? false
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
        case .utf8(let string), .unicodeWithBOM(let string), .latin1(let string):
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

    /// 按字节查找 needle 的各种 Unicode 编码；Latin-1 编码只在内容不是合法 UTF-8 文本时才查找：
    /// 否则 “é”（Latin-1 为 0xE9）会命中 UTF-8 中以 0xE9 开头的汉字（U+9000–U+9FFF）
    private func containsEncoded(_ needle: String, in content: LazyTextContent) -> Bool {
        let data = content.data
        if Self.unicodeEncodedNeedles(for: needle).contains(where: { encoded in
            encoded.withUnsafeBytes { Self.bytesContain($0, in: data) }
        }) {
            return true
        }
        // 纯 ASCII 的 needle 的 Latin-1 编码与 UTF-8 相同，上面已经找过
        guard needle.utf8.contains(where: { $0 >= 0x80 }),
              let latin1 = needle.data(using: .isoLatin1),
              content.mayContainLatin1Text else {
            return false
        }
        return latin1.withUnsafeBytes { Self.bytesContain($0, in: data) }
    }

    /// 不受当前比较选项影响的字符：既没有大小写和变音符号变体，也没有其他 Unicode 组合形式，
    /// 宽松比较下能匹配它的只有它自身的编码
    private static func isFoldInvariant(_ character: Character, compareOptions: String.CompareOptions) -> Bool {
        let value = String(character)
        if compareOptions.contains(.caseInsensitive), value.lowercased() != value || value.uppercased() != value {
            return false
        }
        // 忽略变音符号时，不带变音的字母也能匹配内容中带变音的写法（“e” 匹配 “é”，希伯来文字母匹配带点的写法），
        // 所以能带变音符号的字母一律不能用来按字节预筛
        if compareOptions.contains(.diacriticInsensitive), DiacriticFolding.mayCarryDiacritics(character) {
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

    private static func unicodeEncodedNeedles(for needle: String) -> [Data] {
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

    private func matches(
        candidate: String,
        value: String,
        operator searchOperator: SearchRuleOperator,
        compareOptions: String.CompareOptions,
        regex: NSRegularExpression?
    ) -> Bool {
        switch searchOperator {
        case .contains, .containsPhrase:
            return candidate.range(of: value, options: compareOptions) != nil
        case .beginsWith:
            return candidate.range(of: value, options: compareOptions.union(.anchored)) != nil
        case .endsWith:
            return candidate.range(of: value, options: compareOptions.union(.backwards))?.upperBound == candidate.endIndex
        case .isExactly:
            return candidate.compare(value, options: compareOptions) == .orderedSame
        case .isNot:
            return candidate.compare(value, options: compareOptions) != .orderedSame
        case .doesNotContain:
            return candidate.range(of: value, options: compareOptions) == nil
        case .containsWords:
            return splitTerms(from: value).allSatisfy {
                candidate.range(of: $0, options: compareOptions) != nil
            }
        case .containsAnyOf:
            return splitTerms(from: value).contains {
                candidate.range(of: $0, options: compareOptions) != nil
            }
        case .beginsWithAnyOf:
            return splitTerms(from: value).contains {
                candidate.range(of: $0, options: compareOptions.union(.anchored)) != nil
            }
        case .endsWithAnyOf:
            return splitTerms(from: value).contains {
                candidate.range(of: $0, options: compareOptions.union(.backwards))?.upperBound == candidate.endIndex
            }
        case .isAnyOf:
            return splitTerms(from: value).contains {
                candidate.compare($0, options: compareOptions) == .orderedSame
            }
        case .matchesPattern, .matchesRegex:
            return regex.map { Self.firstMatch($0, in: candidate) } ?? false
        case .doesNotMatchRegex:
            // 非法正则无法判定，按不命中处理，而不是让“不匹配”命中所有文件
            return regex.map { Self.firstMatch($0, in: candidate) == false } ?? false
        case .isGreaterThan, .isLessThan, .isBefore, .isAfter, .isOnOrBefore, .isOnOrAfter, .isWithinTheLast, .isToday, .isYesterday:
            return false
        }
    }

    private static func firstMatch(_ regex: NSRegularExpression, in candidate: String) -> Bool {
        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        return regex.firstMatch(in: candidate, options: [], range: range) != nil
    }

    private func splitTerms(from value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { $0.isEmpty == false }
    }
}

/// 忽略变音符号时哪些字符可能以带变音的形式出现
enum DiacriticFolding {
    /// 拼音文字的字母（拉丁、希腊、西里尔、希伯来、假名等）都可能带组合符号或有带变音的写法（如 “が” = “か” + 浊点）；
    /// 汉字等表意文字与韩文音节没有变音形式，数字、标点、符号也视为不会带变音
    static func mayCarryDiacritics(_ character: Character) -> Bool {
        guard character.isLetter else {
            return false
        }
        let isIdeographOrHangul = character.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isIdeographic || (0xAC00...0xD7A3).contains(scalar.value)
        }
        return isIdeographOrHangul == false
    }
}

/// 文件内容的形态，同一文件判定多个词时只识别一次，且只在字节查找无法定论时才识别
private final class LazyTextContent {
    enum Form {
        /// 不含 NUL 的纯 ASCII 文本
        case ascii
        /// 不含 NUL 的合法 UTF-8 文本
        case utf8(String)
        /// 带 BOM 的 UTF-16 / UTF-32 文本
        case unicodeWithBOM(String)
        /// 不含 NUL、又不是合法 UTF-8 的内容，按 Latin-1 解码
        case latin1(String)
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

    /// 内容中的文字可能是 Latin-1 编码：二进制文件无法确定，按 Latin-1 解码的文本则一定是
    var mayContainLatin1Text: Bool {
        switch form {
        case .binary, .latin1:
            return true
        case .ascii, .utf8, .unicodeWithBOM:
            return false
        }
    }

    /// 解码后的文字；二进制内容返回 nil
    var decodedText: String? {
        switch form {
        case .ascii:
            return String(decoding: data, as: UTF8.self)
        case .utf8(let string), .unicodeWithBOM(let string), .latin1(let string):
            return string
        case .binary:
            return nil
        }
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
            return .unicodeWithBOM(string)
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
        if let string = String(data: data, encoding: .utf8) {
            return .utf8(string)
        }
        if let string = String(data: data, encoding: .isoLatin1) {
            return .latin1(string)
        }
        return .binary
    }
}
