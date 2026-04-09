import Testing
@testable import FileHound

struct SearchWindowStateTests {
    @Test
    func searchingStateDisablesEditingAndUsesStopButton() {
        let state = SearchWindowState(
            phase: .searching(scopeDescription: "Macintosh HD", matchCount: 0)
        )

        #expect(state.isEditingEnabled == false)
        #expect(state.primaryActionTitle == "Stop")
        #expect(state.showsActivityIndicator == true)
        #expect(state.statusText == "Searching: Macintosh HD")
    }

    @Test
    func idleStateShowsFindButtonAndResultCount() {
        let state = SearchWindowState(phase: .idle(matchCount: 4))

        #expect(state.isEditingEnabled == true)
        #expect(state.primaryActionTitle == "Find")
        #expect(state.showsActivityIndicator == false)
        #expect(state.statusText == "Items Found: 4")
    }
}
