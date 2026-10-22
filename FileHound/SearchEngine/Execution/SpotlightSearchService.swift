import Foundation

struct SpotlightSearchService: Sendable {
    /// 执行一条查询，逐条回调命中的路径；shouldStop 返回 true 时尽快结束并正常返回
    typealias StreamingQuery = @Sendable (
        _ rootPath: String,
        _ query: String,
        _ shouldStop: @escaping @Sendable () -> Bool,
        _ onPath: (String) -> Void
    ) throws -> Void

    /// mdfind 偶尔会长时间没有输出（索引重建中、网络卷等），超过这个时长就结束它，已取回的结果保留
    static let defaultTimeout: TimeInterval = 60

    private let runQuery: StreamingQuery

    init() {
        runQuery = { rootPath, query, shouldStop, onPath in
            try Self.streamOutputLines(
                ofExecutableAt: "/usr/bin/mdfind",
                arguments: ["-onlyin", rootPath, query],
                shouldStop: shouldStop,
                onLine: onPath
            )
        }
    }

    init(streamingQuery: @escaping StreamingQuery) {
        runQuery = streamingQuery
    }

    /// 一次性返回全部结果的查询，便于测试注入
    init(runQuery: @escaping @Sendable (_ rootPath: String, _ query: String) throws -> [String]) {
        self.runQuery = { rootPath, query, shouldStop, onPath in
            for path in try runQuery(rootPath, query) {
                if shouldStop() {
                    return
                }
                onPath(path)
            }
        }
    }

    /// 按规则查询并逐条回调；规则无法翻译成 Spotlight 查询时不执行，返回 false
    @discardableResult
    func search(
        rootPath: String,
        rules: [SearchRuleSelection],
        shouldStop: @escaping @Sendable () -> Bool = { false },
        onPath: (String) -> Void
    ) throws -> Bool {
        guard let query = buildQuery(from: rules) else {
            return false
        }

        try runQuery(rootPath, query, shouldStop, onPath)
        return true
    }

    /// 文本内容的子串查询依赖 Spotlight 保存的文本：源码等文件里的中文值或带标点的值（如“05-屏幕截图”）常常查不到，
    /// 但按词仍能查到（索引把“屏幕截图”切成了“屏幕”“截图”两个词）。这时另外按同样的方式分词，
    /// 查询“每个词片段都出现”的文件作为候选；不需要时返回 false。候选只是超集，调用方需读取文件复核
    @discardableResult
    func searchTextContentCandidates(
        rootPath: String,
        rules: [SearchRuleSelection],
        shouldStop: @escaping @Sendable () -> Bool = { false },
        onPath: (String) -> Void
    ) throws -> Bool {
        guard rules.contains(where: Self.needsTokenizedTextQuery),
              let query = buildQuery(from: rules, tokenizingTextContent: true) else {
            return false
        }

        try runQuery(rootPath, query, shouldStop, onPath)
        return true
    }

    /// 内容查询命中的文件能否直接采信、不再读取文件复核：查询与 ContentMatcher 的“包含”语义一致（不区分大小写与变音符号的子串），
    /// 规则也忽略大小写与变音符号时才成立。直接采信的好处是能覆盖 PDF、Office 等读取原始字节无法判定的格式
    static func trustsTextContentHits(caseSensitive: Bool, diacriticsSensitive: Bool) -> Bool {
        caseSensitive == false && diacriticsSensitive == false
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
        guard predicates.count > 1 else {
            return predicates[0]
        }

        // mdfind 中 && 优先级高于 ||，条件内部可能含 ||，每个条件整体加括号再用 && 连接
        return predicates.map { "(\($0))" }.joined(separator: " && ")
    }

    private func buildPredicate(for rule: SearchRuleSelection, tokenizingTextContent: Bool) -> String? {
        let trimmedValue = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false else {
            return nil
        }

        switch rule.field {
        case .name:
            return predicate(for: "kMDItemFSName", value: trimmedValue, operator: rule.operator)
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
            return textContentQuery(for: trimmedValue, operator: rule.operator)
        default:
            // kMDItemPath 等属性不能用于查询，不翻译
            return nil
        }
    }

    /// 只查文本内容属性：不带属性名的自由文本查询（"value"）还会匹配文件名、作者等元数据，甚至命中文件夹，
    /// 而且按词前缀匹配，与“包含”语义不一致
    private func textContentQuery(for value: String, operator searchOperator: SearchRuleOperator) -> String? {
        func contentContains(_ text: String) -> String {
            "kMDItemTextContent == \"*\(escapeForQuery(text))*\"cd"
        }

        let tokens = splitTerms(from: value)
        guard tokens.isEmpty == false else {
            return nil
        }

        switch searchOperator {
        case .contains, .containsPhrase:
            return contentContains(value)
        case .containsWords:
            return tokens.map(contentContains).joined(separator: " && ")
        case .containsAnyOf:
            return tokens.map(contentContains).joined(separator: " || ")
        case .isAnyOf, .isNot, .beginsWith, .endsWith, .isExactly, .doesNotContain, .matchesPattern, .beginsWithAnyOf, .endsWithAnyOf, .matchesRegex, .doesNotMatchRegex, .isGreaterThan, .isLessThan, .isBefore, .isAfter, .isOnOrBefore, .isOnOrAfter, .isWithinTheLast, .isToday, .isYesterday:
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

    /// 转义查询字符串中的特殊字符：反斜杠、引号，以及会被当作通配符的 “*”
    func escapeForQuery(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*")
    }

    /// 运行命令并按行返回其标准输出（测试与一次性调用使用）
    static func outputLines(ofExecutableAt executablePath: String, arguments: [String]) throws -> [String] {
        var lines: [String] = []
        try streamOutputLines(ofExecutableAt: executablePath, arguments: arguments) { lines.append($0) }
        return lines
    }

    /// 运行命令，边读边按行回调标准输出。shouldStop 返回 true 或超时后结束进程：停止时正常返回已读到的部分，
    /// 超时时在回调完已读到的部分后抛出 timedOut
    static func streamOutputLines(
        ofExecutableAt executablePath: String,
        arguments: [String],
        timeout: TimeInterval = defaultTimeout,
        shouldStop: @escaping @Sendable () -> Bool = { false },
        onLine: (String) -> Void
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        let exited = DispatchGroup()
        exited.enter()
        process.terminationHandler = { _ in exited.leave() }
        try process.run()

        // 看门狗线程：读取线程阻塞在管道上时也能响应停止与超时。结束进程后管道随之关闭，读取循环自然退出
        let monitor = ProcessStopReason()
        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global(qos: .utility).async {
            while exited.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
                if shouldStop() {
                    monitor.record(.stopped)
                    process.terminate()
                } else if DispatchTime.now() >= deadline {
                    monitor.record(.timedOut)
                    process.terminate()
                }
            }
        }

        // 一直读到管道关闭（而不是进程退出），mdfind 分批输出、退出前写入的最后一批不会丢。
        // 结束进程后管道随之关闭；若被结束的进程留下了仍持有管道的子进程，读取会等到子进程退出（mdfind 不会这样）
        // 用 read(2) 读取：有数据就返回，结果能边产生边回调；FileHandle.read(upToCount:) 会等凑满或读到结尾才返回
        let descriptor = outputPipe.fileHandleForReading.fileDescriptor
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
        defer { buffer.deallocate() }
        var pending = Data()
        while true {
            let count = read(descriptor, buffer, bufferSize)
            if count < 0, errno == EINTR {
                continue
            }
            guard count > 0 else {
                break
            }
            pending.append(buffer.assumingMemoryBound(to: UInt8.self), count: count)
            var lineStart = pending.startIndex
            while let newline = pending[lineStart...].firstIndex(of: 0x0A) {
                if newline > lineStart {
                    onLine(String(decoding: pending[lineStart..<newline], as: UTF8.self))
                }
                lineStart = pending.index(after: newline)
            }
            pending = Data(pending[lineStart...])
        }
        if pending.isEmpty == false {
            onLine(String(decoding: pending, as: UTF8.self))
        }
        exited.wait()

        switch monitor.reason {
        case .stopped:
            return
        case .timedOut:
            throw SpotlightSearchError.timedOut
        case nil:
            break
        }
        guard process.terminationStatus == 0 else {
            throw SpotlightSearchError.queryFailed(status: process.terminationStatus)
        }
    }
}

/// 看门狗记录的结束原因，只记第一次
private final class ProcessStopReason: @unchecked Sendable {
    enum Reason {
        case stopped
        case timedOut
    }

    private let lock = NSLock()
    private var storage: Reason?

    var reason: Reason? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ reason: Reason) {
        lock.lock()
        if storage == nil {
            storage = reason
        }
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
    case timedOut
}
