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
            return L10n.string("search_window.action.stop")
        }
        return L10n.string("search_window.action.find")
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
            return L10n.format("search_window.status.items_found", matchCount)
        case .editing(let matchCount):
            return L10n.format("search_window.status.items_found", matchCount ?? 0)
        case .searching(let scopeDescription, let matchCount):
            return L10n.format("search_window.status.searching", scopeDescription, matchCount)
        }
    }
}
