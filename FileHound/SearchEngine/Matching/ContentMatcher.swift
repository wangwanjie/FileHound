import Foundation

struct ContentMatcher: Sendable {
    func matches(data: Data, query: QueryRule) throws -> Bool {
        let text = String(decoding: data, as: UTF8.self)

        switch query {
        case .contentContains(let needle):
            return text.localizedCaseInsensitiveContains(needle)
        case .contentMatchesRegex(let pattern):
            return text.range(of: pattern, options: .regularExpression) != nil
        default:
            return false
        }
    }
}
