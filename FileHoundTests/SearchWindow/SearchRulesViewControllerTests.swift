import AppKit
import Testing
@testable import FileHound

struct SearchRulesViewControllerTests {
    @MainActor
    @Test
    func addAndRemoveButtonsAdjustRuleRows() {
        let controller = SearchRulesViewController()
        _ = controller.view

        let listView = try! #require(controller.view as? SearchRuleListView)
        let firstRow = try! #require(listView.stackView.arrangedSubviews.first as? SearchRuleRowView)
        firstRow.addButton.performClick(nil)

        #expect(listView.stackView.arrangedSubviews.count == 2)

        let secondRow = try! #require(listView.stackView.arrangedSubviews.last as? SearchRuleRowView)
        secondRow.removeButton.performClick(nil)

        #expect(listView.stackView.arrangedSubviews.count == 1)
    }
}
