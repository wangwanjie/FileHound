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

    @MainActor
    @Test
    func addingRuleIncreasesPreferredContentHeight() {
        let controller = SearchRulesViewController()
        _ = controller.view

        let initialHeight = controller.preferredContentHeight
        let listView = try! #require(controller.view as? SearchRuleListView)
        let firstRow = try! #require(listView.stackView.arrangedSubviews.first as? SearchRuleRowView)
        firstRow.addButton.performClick(nil)

        #expect(controller.preferredContentHeight > initialHeight)
    }

    @MainActor
    @Test
    func valueFieldIsEditableAndAlignedWithOtherControls() {
        let row = SearchRuleRowView()
        row.frame = NSRect(x: 0, y: 0, width: 900, height: 44)
        row.layoutSubtreeIfNeeded()
        let valueFieldFrame = row.valueField.convert(row.valueField.bounds, to: row)

        #expect(row.valueField.isEditable == true)
        #expect(row.valueField.isSelectable == true)
        #expect(abs(row.fieldPopup.frame.midY - valueFieldFrame.midY) < 1.0)
    }

    @MainActor
    @Test
    func valueFieldNormalizesNewlinesIntoSingleLineText() {
        let row = SearchRuleRowView()
        row.valueField.stringValue = "32x32\nicon"

        row.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))

        #expect(row.valueField.stringValue == "32x32 icon")
    }

    @MainActor
    @Test
    func toggleFieldsUseToggleEditorAndLogicSummaryTracksMultipleRows() {
        let controller = SearchRulesViewController()
        _ = controller.view

        controller.applySelections([
            SearchRuleSelection(field: .name, operator: .contains, value: "report"),
            SearchRuleSelection(field: .invisibleItems, operator: .isExactly, value: "true")
        ])

        let listView = try! #require(controller.view as? SearchRuleListView)
        let secondRow = try! #require(listView.stackView.arrangedSubviews.last as? SearchRuleRowView)

        #expect(secondRow.debugUsesToggleEditor == true)
        #expect(controller.debugLogicSummary.contains(SearchRuleField.name.localizedTitle))
        #expect(controller.debugLogicSummary.contains(SearchRuleField.invisibleItems.localizedTitle))
    }

    @MainActor
    @Test
    func kindAndRelativeDateFieldsUseDedicatedEditors() {
        let row = SearchRuleRowView()

        row.apply(selection: SearchRuleSelection(field: .kind, operator: .isExactly, value: "kind.application"))
        #expect(row.debugUsesChoiceEditor == true)

        row.apply(selection: SearchRuleSelection(field: .lastModifiedDate, operator: .isWithinTheLast, value: "7|day"))
        #expect(row.debugUsesRelativeDateEditor == true)
    }

    @MainActor
    @Test
    func unsupportedFieldsAreDisabledAndInvalidRulesExposeBlockingSummary() {
        let row = SearchRuleRowView()
        let commentsIndex = try! #require(SearchRuleField.allCases.firstIndex(of: .comments))
        let commentsItem = try! #require(row.fieldPopup.item(at: commentsIndex))
        #expect(commentsItem.isEnabled == false)

        let controller = SearchRulesViewController()
        _ = controller.view

        controller.applySelections([
            SearchRuleSelection(field: .kind, operator: .isNot, value: "kind.any")
        ])

        #expect(controller.debugCanSearch == false)
        #expect(controller.debugBlockingMessage == L10n.string("search_rule.validation.kind_not_any"))
    }

    @MainActor
    @Test
    func scrollingRuleListKeepsRowHeightsAndExpandsDocumentView() {
        let controller = SearchRulesViewController()
        let listView = try! #require(controller.view as? SearchRuleListView)

        controller.applySelections((0..<10).map { index in
            SearchRuleSelection(field: .name, operator: .contains, value: "report-\(index)")
        })
        controller.setScrollingEnabled(true)
        listView.frame = NSRect(x: 0, y: 0, width: 920, height: 180)
        listView.layoutSubtreeIfNeeded()

        let rowHeights = listView.stackView.arrangedSubviews.map(\.frame.height)
        #expect(rowHeights.allSatisfy { $0 >= 40 })
        #expect(listView.debugDocumentContentHeight > listView.debugVisibleContentHeight)
    }

    @MainActor
    @Test
    func ruleListBackgroundRefreshesAcrossAppearances() {
        let listView = SearchRuleListView()

        let light = listView.debugBackgroundHex(for: .aqua)
        let dark = listView.debugBackgroundHex(for: .darkAqua)

        #expect(light != dark)
    }
}
