import Testing
@testable import FileHound

struct SearchWindowStateTests {
    @Test
    func searchingStateDisablesEditingAndUsesStopButton() {
        let state = SearchWindowState(
            phase: .searching(scopeDescription: "Macintosh HD", matchCount: 0)
        )

        #expect(state.isEditingEnabled == false)
        #expect(state.primaryActionTitle == L10n.string("search_window.action.stop"))
        #expect(state.showsActivityIndicator == true)
        #expect(state.statusText == L10n.format("search_window.status.searching", "Macintosh HD", 0))
    }

    @Test
    func idleStateShowsFindButtonAndResultCount() {
        let state = SearchWindowState(phase: .idle(matchCount: 4))

        #expect(state.isEditingEnabled == true)
        #expect(state.primaryActionTitle == L10n.string("search_window.action.find"))
        #expect(state.showsActivityIndicator == false)
        #expect(state.statusText == L10n.format("search_window.status.items_found", 4))
    }
}
