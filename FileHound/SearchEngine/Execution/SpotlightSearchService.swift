import Foundation

struct SpotlightSearchService: Sendable {
    private let runQuery: @Sendable (_ rootPath: String, _ query: String) throws -> [String]

    init(
        runQuery: @escaping @Sendable (_ rootPath: String, _ query: String) throws -> [String] = { rootPath, query in
            try Self.runProcess(rootPath: rootPath, query: query)
        }
    ) {
        self.runQuery = runQuery
    }

    func search(rootPath: String, rules: [SearchRuleSelection]) throws -> [String]? {
        guard let query = buildQuery(from: rules) else {
            return nil
        }

        return try runQuery(rootPath, query)
    }

    /// 文本内容的短语查询依赖 Spotlight 的分词：值里带标点（如“05-屏幕截图”）或含中日文时整句查询常常查不到，
    /// 因为索引把“屏幕截图”切成了“屏幕”“截图”两个词。这时另外按同样的方式分词，查询“每个词片段都出现”的文件作为候选，
    /// 返回 nil 表示不需要；候选只是超集，调用方需读取文件复核
    func searchTextContentCandidates(rootPath: String, rules: [SearchRuleSelection]) throws -> [String]? {
        guard rules.contains(where: Self.needsTokenizedTextQuery),
              let query = buildQuery(from: rules, tokenizingTextContent: true) else {
            return nil
        }

        return try runQuery(rootPath, query)
    }

    func canSatisfyTextContentSearch(
        rules: [SearchRuleSelection],
        caseSensitive: Bool,
        diacriticsSensitive: Bool
    ) -> Bool {
        guard caseSensitive == false, diacriticsSensitive == false else {
            return false
        }

        return rules.contains(where: { $0.field == .textContent }) && buildQuery(from: rules) != nil
    }

    func buildQuery(from rules: [SearchRuleSelection], tokenizingTextContent: Bool = false) -> String? {
        var predicates: [String] = []

        for rule in rules {
            let trimmedValue = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)

            if Self.filterOnlyFields.contains(rule.field) || trimmedValue.isEmpty {
                continue
            }

            guard let predicate = buildPredicate(for: rule, tokenizingTextContent: tokenizingTextContent) else {
                return nil
            }

            predicates.append(predicate)
        }

        guard predicates.isEmpty == false else {
            return nil
        }

        return predicates.joined(separator: " && ")
    }

    private func buildPredicate(for rule: SearchRuleSelection, tokenizingTextContent: Bool) -> String? {
        let trimmedValue = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false else {
            return nil
        }

        switch rule.field {
        case .name:
            return predicate(for: "kMDItemFSName", value: trimmedValue, operator: rule.operator)
        case .path:
            return predicate(for: "kMDItemPath", value: trimmedValue, operator: rule.operator)
        case .extensionName:
            let normalizedValue = trimmedValue.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return extensionPredicate(value: normalizedValue, operator: rule.operator)
        case .comments:
            return predicate(for: "kMDItemFinderComment", value: trimmedValue, operator: rule.operator)
        case .textContent:
            if tokenizingTextContent, Self.needsTokenizedTextQuery(rule) {
                // 词片段两端都加通配，值的首尾落在索引词的中间（如“幕截图”里的“幕”）时也能命中
                return Self.spotlightTokens(of: trimmedValue)
                    .map { "kMDItemTextContent == \"*\(escapeForQuery($0))*\"cdw" }
                    .joined(separator: " && ")
            }
            return freeTextQuery(for: trimmedValue, operator: rule.operator)
        default:
            return nil
        }
    }

    private func freeTextQuery(for value: String, operator searchOperator: SearchRuleOperator) -> String? {
        let tokens = splitTerms(from: value)
        guard tokens.isEmpty == false else {
            return nil
        }

        switch searchOperator {
        case .contains, .containsPhrase:
            return "\"\(escapeForQuery(value))\""
        case .containsWords:
            return tokens.map { "\"\(escapeForQuery($0))\"" }.joined(separator: " && ")
        case .containsAnyOf, .isAnyOf:
            return tokens.map { "\"\(escapeForQuery($0))\"" }.joined(separator: " || ")
        case .isNot, .beginsWith, .endsWith, .isExactly, .doesNotContain, .matchesPattern, .beginsWithAnyOf, .endsWithAnyOf, .matchesRegex, .doesNotMatchRegex, .isGreaterThan, .isLessThan, .isBefore, .isAfter, .isOnOrBefore, .isOnOrAfter, .isWithinTheLast, .isToday, .isYesterday:
            return nil
        }
    }

    private func predicate(
        for field: String,
        value: String,
        operator searchOperator: SearchRuleOperator
    ) -> String? {
        let tokens = splitTerms(from: value)
        guard tokens.isEmpty == false else {
            return nil
        }

        let patterns: [String]
        switch searchOperator {
        case .contains, .containsPhrase:
            patterns = tokens.map { "*\(escapeForQuery($0))*" }
            return patterns.map { "\(field) == '\($0)'cd" }.joined(separator: " && ")
        case .beginsWith:
            patterns = tokens.map { "\(escapeForQuery($0))*" }
            return patterns.map { "\(field) == '\($0)'cd" }.joined(separator: " && ")
        case .endsWith:
            patterns = tokens.map { "*\(escapeForQuery($0))" }
            return patterns.map { "\(field) == '\($0)'cd" }.joined(separator: " && ")
        case .isExactly:
            return tokens.map { "\(field) == '\(escapeForQuery($0))'cd" }.joined(separator: " && ")
        case .containsAnyOf:
            return tokens.map { "\(field) == '*\(escapeForQuery($0))*'cd" }.joined(separator: " || ")
        case .isAnyOf:
            return tokens.map { "\(field) == '\(escapeForQuery($0))'cd" }.joined(separator: " || ")
        case .isNot, .doesNotContain, .containsWords, .matchesPattern, .beginsWithAnyOf, .endsWithAnyOf, .matchesRegex, .doesNotMatchRegex, .isGreaterThan, .isLessThan, .isBefore, .isAfter, .isOnOrBefore, .isOnOrAfter, .isWithinTheLast, .isToday, .isYesterday:
            return nil
        }
    }

    /// 扩展名是文件名最后一个 “.” 之后的部分，转成对 kMDItemFSName 的通配匹配；
    /// 生成的条件是结果的超集，候选项随后会按完整规则复核
    private func extensionPredicate(value: String, operator searchOperator: SearchRuleOperator) -> String? {
        guard value.isEmpty == false else {
            return nil
        }

        func namePattern(_ pattern: String) -> String {
            "kMDItemFSName == '\(pattern)'cd"
        }

        let escaped = escapeForQuery(value)
        let escapedTerms = splitTerms(from: value).map(escapeForQuery)
        switch searchOperator {
        case .isExactly:
            return namePattern("*.\(escaped)")
        case .beginsWith:
            return namePattern("*.\(escaped)*")
        case .endsWith:
            return namePattern("*\(escaped)")
        case .contains:
            return namePattern("*.*\(escaped)*")
        case .isAnyOf:
            return escapedTerms.isEmpty ? nil : escapedTerms.map { namePattern("*.\($0)") }.joined(separator: " || ")
        case .beginsWithAnyOf:
            return escapedTerms.isEmpty ? nil : escapedTerms.map { namePattern("*.\($0)*") }.joined(separator: " || ")
        case .endsWithAnyOf:
            return escapedTerms.isEmpty ? nil : escapedTerms.map { namePattern("*\($0)") }.joined(separator: " || ")
        case .containsAnyOf:
            return escapedTerms.isEmpty ? nil : escapedTerms.map { namePattern("*.*\($0)*") }.joined(separator: " || ")
        case .isNot, .doesNotContain, .containsPhrase, .containsWords, .matchesPattern, .matchesRegex, .doesNotMatchRegex, .isGreaterThan, .isLessThan, .isBefore, .isAfter, .isOnOrBefore, .isOnOrAfter, .isWithinTheLast, .isToday, .isYesterday:
            return nil
        }
    }

    private static func needsTokenizedTextQuery(_ rule: SearchRuleSelection) -> Bool {
        guard rule.field == .textContent, rule.operator == .contains || rule.operator == .containsPhrase else {
            return false
        }
        let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = spotlightTokens(of: value)
        guard tokens.isEmpty == false else {
            return false
        }
        // 只含 ASCII 的单个词整句查询就能查到；非 ASCII 的值可能被索引切成多个词，或只是索引词的一部分
        return tokens != [value] || value.unicodeScalars.contains { $0.isASCII == false }
    }

    /// 按系统的分词规则（与 Spotlight 建索引时一致）把值切成词，中日文会按词典切分
    static func spotlightTokens(of value: String) -> [String] {
        let string = value as NSString
        let tokenizer = CFStringTokenizerCreate(
            nil,
            value as CFString,
            CFRange(location: 0, length: string.length),
            kCFStringTokenizerUnitWord,
            nil
        )
        var tokens: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty == false {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            tokens.append(string.substring(with: NSRange(location: range.location, length: range.length)))
        }
        return tokens
    }

    private func splitTerms(from value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { $0.isEmpty == false }
    }

    private func escapeForQuery(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runProcess(rootPath: String, query: String) throws -> [String] {
        try outputLines(ofExecutableAt: "/usr/bin/mdfind", arguments: ["-onlyin", rootPath, query])
    }

    /// 运行命令并按行返回其标准输出；任务取消时结束进程并抛出 CancellationError
    static func outputLines(ofExecutableAt executablePath: String, arguments: [String]) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()

        // 在单独的线程上一直读到管道关闭，避免结果超过管道缓冲区后 mdfind 阻塞在写入上。
        // 不能用 readabilityHandler：进程退出时它可能正读着最后一批输出，取结果时这批会丢失
        // （mdfind 会分批输出，整盘文本查询常常只剩第一批）
        let buffer = ProcessOutputBuffer()
        let finishedReading = DispatchSemaphore(value: 0)
        let reader = outputPipe.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async {
            buffer.append(reader.readDataToEndOfFile())
            finishedReading.signal()
        }

        while exited.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if Task.isCancelled {
                process.terminate()
            }
        }
        finishedReading.wait()

        if Task.isCancelled {
            throw CancellationError()
        }
        guard process.terminationStatus == 0 else {
            throw SpotlightSearchError.queryFailed(status: process.terminationStatus)
        }

        return String(decoding: buffer.data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.isEmpty == false }
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ chunk: Data) {
        guard chunk.isEmpty == false else {
            return
        }
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }
}

private extension SpotlightSearchService {
    static let filterOnlyFields: Set<SearchRuleField> = [
        .caseSensitive,
        .diacriticsSensitive,
        .invisibleItems,
        .packageContents,
        .trashedContents,
        .limitFolderDepth,
        .limitAmount
    ]
}

enum SpotlightSearchError: Error {
    case queryFailed(status: Int32)
}
