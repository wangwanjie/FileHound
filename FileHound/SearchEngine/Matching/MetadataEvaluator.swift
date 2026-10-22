import Foundation

/// 搜索开始时对每条规则做一次的预处理：规范化值、拆分词、编译正则、解析日期界限与字节数。
/// 遍历时每个条目都要逐条判定规则，匹配阶段只做比较，不再重复解析（DateFormatter、NSRegularExpression 的创建开销都很大）
struct PreparedSearchRule: @unchecked Sendable {
    let field: SearchRuleField
    let `operator`: SearchRuleOperator
    /// 规范化后的值：去掉首尾空白，扩展名再去掉首尾的 “.”
    let value: String
    /// 按逗号与空白拆分出的词，供“包含任一”“是任一”等运算符使用
    let terms: [String]
    /// 正则与通配符运算符预先编译的正则；非法正则为 nil，此时肯定与否定运算符都不命中
    let regex: NSRegularExpression?
    /// “包含短语”（一个）与“包含单词”（每个词一个）按单词边界匹配的正则，已按变音设置折叠
    let wordRegexes: [NSRegularExpression]
    /// 文件大小规则解析出的字节数
    let byteCount: Int64?
    /// 日期规则解析出的时间区间；解析失败时为 nil，规则不命中任何条目
    let dateRange: SearchDateRange?

    init(
        _ rule: SearchRuleSelection,
        caseSensitive: Bool,
        diacriticsSensitive: Bool,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        field = rule.field
        `operator` = rule.operator
        var normalizedValue = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.field == .extensionName {
            normalizedValue = normalizedValue.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        value = normalizedValue
        terms = Self.splitTerms(from: normalizedValue)

        switch rule.operator {
        case .matchesRegex, .doesNotMatchRegex, .matchesPattern:
            regex = ContentMatcher.compileRegex(for: rule.operator, value: normalizedValue, caseSensitive: caseSensitive)
        default:
            regex = nil
        }

        switch rule.operator {
        case .containsPhrase:
            wordRegexes = [Self.wholeWordRegex(for: normalizedValue, caseSensitive: caseSensitive, diacriticsSensitive: diacriticsSensitive)]
                .compactMap { $0 }
        case .containsWords:
            wordRegexes = terms.compactMap {
                Self.wholeWordRegex(for: $0, caseSensitive: caseSensitive, diacriticsSensitive: diacriticsSensitive)
            }
        default:
            wordRegexes = []
        }

        byteCount = rule.field == .fileSize ? SearchRuleNumberParser.parseByteCount(normalizedValue) : nil

        switch rule.field {
        case .lastModifiedDate, .createdDate, .lastOpenedDate:
            dateRange = SearchDateRange(operator: rule.operator, value: normalizedValue, now: now, calendar: calendar)
        default:
            dateRange = nil
        }
    }

    var selection: SearchRuleSelection {
        SearchRuleSelection(field: field, operator: `operator`, value: value)
    }

    /// 判定前需要 attributesOfItem 的规则。非“包含”类的文本内容规则要先看文件大小，超大文件不必读取
    var needsAttributes: Bool {
        switch field {
        case .lastModifiedDate, .createdDate, .fileSize, .kind, .script:
            return true
        case .textContent:
            return ContentMatcher.isContainsOperator(`operator`) == false
        default:
            return false
        }
    }

    /// 以单词边界匹配短语，避免 “port” 命中 “report”；忽略变音符号时短语先折叠，候选文字匹配前同样折叠
    private static func wholeWordRegex(for phrase: String, caseSensitive: Bool, diacriticsSensitive: Bool) -> NSRegularExpression? {
        let foldedPhrase = diacriticsSensitive ? phrase : phrase.folding(options: .diacriticInsensitive, locale: nil)
        let words = foldedPhrase.split(whereSeparator: \.isWhitespace).map {
            NSRegularExpression.escapedPattern(for: String($0))
        }
        guard words.isEmpty == false else {
            return nil
        }
        let pattern = "(?<![\\p{L}\\p{N}_])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}_])"
        return try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
    }

    private static func splitTerms(from value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { $0.isEmpty == false }
    }
}

/// 日期规则对应的半开区间 [lower, upper)，缺省的一端不限
struct SearchDateRange: Equatable, Sendable {
    let lower: Date?
    let upper: Date?

    init(lower: Date?, upper: Date?) {
        self.lower = lower
        self.upper = upper
    }

    /// 按运算符换算成区间。“今天”“昨天”“最近”都以 now 为准，方便测试注入时钟
    init?(operator searchOperator: SearchRuleOperator, value: String, now: Date, calendar: Calendar) {
        func dayBounds(of date: Date) -> (start: Date, nextStart: Date)? {
            let start = calendar.startOfDay(for: date)
            guard let nextStart = calendar.date(byAdding: .day, value: 1, to: start) else {
                return nil
            }
            return (start, nextStart)
        }

        switch searchOperator {
        case .isToday:
            guard let today = dayBounds(of: now) else {
                return nil
            }
            self.init(lower: today.start, upper: today.nextStart)
        case .isYesterday:
            guard let today = dayBounds(of: now),
                  let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: today.start) else {
                return nil
            }
            self.init(lower: yesterdayStart, upper: today.start)
        case .isWithinTheLast:
            let relative = SearchRuleRelativeDateValue.parse(value)
            guard let amount = relative.positiveAmount, let unit = relative.unit else {
                return nil
            }
            let component: Calendar.Component
            switch unit {
            case .day:
                component = .day
            case .week:
                component = .weekOfYear
            case .month:
                component = .month
            }
            guard let cutoff = calendar.date(byAdding: component, value: -amount, to: now) else {
                return nil
            }
            self.init(lower: cutoff, upper: nil)
        case .isExactly, .isBefore, .isAfter, .isOnOrAfter, .isOnOrBefore:
            guard let target = SearchRuleDateParser.parse(value), let day = dayBounds(of: target) else {
                return nil
            }
            switch searchOperator {
            case .isExactly:
                self.init(lower: day.start, upper: day.nextStart)
            case .isBefore:
                self.init(lower: nil, upper: day.start)
            case .isAfter:
                // “晚于某天”从次日零点起算，不用 23:59:59，避免漏掉最后一秒内的亚秒时间
                self.init(lower: day.nextStart, upper: nil)
            case .isOnOrAfter:
                self.init(lower: day.start, upper: nil)
            default:
                self.init(lower: nil, upper: day.nextStart)
            }
        default:
            return nil
        }
    }

    func contains(_ date: Date) -> Bool {
        if let lower, date < lower {
            return false
        }
        if let upper, date >= upper {
            return false
        }
        return true
    }
}
