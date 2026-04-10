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

    func buildQuery(from rules: [SearchRuleSelection]) -> String? {
        let predicates = rules.compactMap(buildPredicate(for:))
        guard predicates.count == rules.count, predicates.isEmpty == false else {
            return nil
        }

        return predicates.joined(separator: " && ")
    }

    private func buildPredicate(for rule: SearchRuleSelection) -> String? {
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
            return predicate(for: "kMDItemFSName", value: ".\(trimmedValue)", operator: rule.operator, treatAsSuffix: true)
        default:
            return nil
        }
    }

    private func predicate(
        for field: String,
        value: String,
        operator searchOperator: SearchRuleOperator,
        treatAsSuffix: Bool = false
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
        default:
            if treatAsSuffix, searchOperator == .contains {
                return "\(field) == '*\(escapeForQuery(value))'cd"
            }
            return nil
        }
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", rootPath, query]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SpotlightSearchError.queryFailed(status: process.terminationStatus)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return output
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.isEmpty == false }
    }
}

enum SpotlightSearchError: Error {
    case queryFailed(status: Int32)
}
