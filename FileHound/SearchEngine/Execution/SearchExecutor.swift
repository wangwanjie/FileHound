import Foundation

struct SearchExecutionResult: Sendable {
    let title: String
    let items: [SearchResultItem]
}

struct SearchExecutor: Sendable {
    private let walker: DirectoryWalker
    private let provider: any FilesystemAccessProviding
    private let spotlightSearchService: SpotlightSearchService
    private let metadataEvaluator = MetadataEvaluator()
    private let contentMatcher = ContentMatcher()

    init(
        walker: DirectoryWalker = DirectoryWalker(),
        provider: any FilesystemAccessProviding = LocalFilesystemProvider(),
        spotlightSearchService: SpotlightSearchService = SpotlightSearchService()
    ) {
        self.walker = walker
        self.provider = provider
        self.spotlightSearchService = spotlightSearchService
    }

    func execute(request: SearchRequest) -> SearchExecutionResult {
        if let spotlightItems = executeSpotlightSearchIfPossible(request: request) {
            return SearchExecutionResult(title: title(for: request.rules), items: spotlightItems)
        }

        let plan = SearchPlan(
            rootPaths: [request.rootPath],
            rootGroup: .all([]),
            excludedPathFragments: [],
            providerKind: .local,
            shouldScanContents: request.rules.contains(where: { $0.field == .textContent })
        )

        do {
            let entries = try walker.walk(plan: plan, includeHiddenFiles: true)
            var items: [SearchResultItem] = []

            for entry in entries {
                guard Task.isCancelled == false else {
                    break
                }

                do {
                    guard try request.rules.allSatisfy({ try matches(entry: entry, rule: $0) }) else {
                        continue
                    }

                    items.append(try makeResultItem(for: entry, preview: request.rules.first?.value ?? ""))
                } catch {
                    continue
                }
            }

            return SearchExecutionResult(title: title(for: request.rules), items: items)
        } catch {
            return SearchExecutionResult(title: title(for: request.rules), items: [])
        }
    }

    private func executeSpotlightSearchIfPossible(request: SearchRequest) -> [SearchResultItem]? {
        guard let paths = try? spotlightSearchService.search(rootPath: request.rootPath, rules: request.rules) else {
            return nil
        }

        let uniquePaths = Array(Set(paths)).sorted()
        let preview = request.rules.first?.value ?? ""

        return uniquePaths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else {
                return nil
            }

            let isDirectory = (try? provider.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeDirectory
            let entry = DirectoryEntry(
                path: path,
                isDirectory: isDirectory,
                isHidden: URL(fileURLWithPath: path).lastPathComponent.hasPrefix(".")
            )

            do {
                return try makeResultItem(for: entry, preview: preview)
            } catch {
                return nil
            }
        }
    }

    private func matches(entry: DirectoryEntry, rule: SearchRuleSelection) throws -> Bool {
        let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            return true
        }

        switch rule.field {
        case .name:
            return matchString(entry.lastPathComponent, using: rule)
        case .extensionName:
            return matchString(URL(fileURLWithPath: entry.path).pathExtension, using: rule)
        case .nameWithoutExtension:
            let name = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
            return matchString(name, using: rule)
        case .path:
            return matchString(entry.path, using: rule)
        case .folderNames:
            return matchString((entry.path as NSString).deletingLastPathComponent, using: rule)
        case .textContent:
            guard entry.isDirectory == false else {
                return false
            }

            let data = try provider.contentsOfFile(atPath: entry.path)
            let query: QueryRule = rule.operator == .matchesRegex
                ? .contentMatchesRegex(rule.value)
                : .contentContains(rule.value)
            return try contentMatcher.matches(data: data, query: query)
        default:
            return matchString(entry.lastPathComponent, using: rule)
        }
    }

    private func makeResultItem(for entry: DirectoryEntry, preview: String) throws -> SearchResultItem {
        let attributes = try provider.attributesOfItem(atPath: entry.path)
        return SearchResultItem(
            path: entry.path,
            matchReason: entry.isDirectory ? "文件夹命中" : "名称命中",
            previewSnippet: preview,
            kind: entry.isDirectory ? "Folder" : "Document",
            modifiedText: Self.displayModifiedDate(attributes: attributes),
            sizeText: Self.displaySize(attributes: attributes),
            enclosingFolder: (entry.path as NSString).deletingLastPathComponent,
            isInvisible: entry.isHidden,
            isPackage: URL(fileURLWithPath: entry.path).pathExtension == "app"
        )
    }

    private func matchString(_ candidate: String, using rule: SearchRuleSelection) -> Bool {
        let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        switch rule.operator {
        case .contains, .containsPhrase:
            return candidate.range(of: value, options: options) != nil
        case .beginsWith:
            return candidate.range(of: value, options: options.union(.anchored)) != nil
        case .endsWith:
            return candidate.range(of: value, options: options.union(.backwards))?.upperBound == candidate.endIndex
        case .isExactly:
            return candidate.compare(value, options: options) == .orderedSame
        case .doesNotContain:
            return candidate.range(of: value, options: options) == nil
        case .containsWords:
            return splitTerms(from: value).allSatisfy { candidate.range(of: $0, options: options) != nil }
        case .matchesPattern:
            return matchRegex(candidate, pattern: wildcardPattern(from: value))
        case .containsAnyOf:
            return splitTerms(from: value).contains { candidate.range(of: $0, options: options) != nil }
        case .beginsWithAnyOf:
            return splitTerms(from: value).contains { candidate.range(of: $0, options: options.union(.anchored)) != nil }
        case .endsWithAnyOf:
            return splitTerms(from: value).contains {
                candidate.range(of: $0, options: options.union(.backwards))?.upperBound == candidate.endIndex
            }
        case .isAnyOf:
            return splitTerms(from: value).contains { candidate.compare($0, options: options) == .orderedSame }
        case .matchesRegex:
            return matchRegex(candidate, pattern: value)
        case .doesNotMatchRegex:
            return matchRegex(candidate, pattern: value) == false
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

    private func matchRegex(_ candidate: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }

        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        return regex.firstMatch(in: candidate, options: [], range: range) != nil
    }

    private func title(for rules: [SearchRuleSelection]) -> String {
        rules.map { "\($0.field.rawValue) \($0.operator.rawValue) \($0.value)" }
            .joined(separator: " and ")
    }

    private static func displayModifiedDate(attributes: [FileAttributeKey: Any]) -> String {
        guard let date = attributes[.modificationDate] as? Date else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d, h:mm:ss a"
        return formatter.string(from: date)
    }

    private static func displaySize(attributes: [FileAttributeKey: Any]) -> String {
        guard let size = attributes[.size] as? NSNumber else {
            return ""
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size.int64Value)
    }
}
