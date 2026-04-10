import Foundation

enum SearchWindowPhase: Equatable, Sendable {
    case idle(matchCount: Int)
    case editing(matchCount: Int?)
    case searching(scopeDescription: String, matchCount: Int)

    var isSearching: Bool {
        if case .searching = self {
            return true
        }
        return false
    }
}

struct SearchWindowState: Equatable, Sendable {
    var phase: SearchWindowPhase

    var isEditingEnabled: Bool {
        if case .searching = phase {
            return false
        }
        return true
    }

    var primaryActionTitle: String {
        if case .searching = phase {
            return "Stop"
        }
        return "Find"
    }

    var showsActivityIndicator: Bool {
        if case .searching = phase {
            return true
        }
        return false
    }

    var statusText: String {
        switch phase {
        case .idle(let matchCount):
            return "Items Found: \(matchCount)"
        case .editing(let matchCount):
            return "Items Found: \(matchCount ?? 0)"
        case .searching(let scopeDescription, _):
            return "Searching: \(scopeDescription)"
        }
    }
}
