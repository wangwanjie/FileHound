import AppKit
import Testing
@testable import FileHound

struct ResultsAppearanceTests {
    @Test
    func readsFontSizeAndDimColorFromSettings() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        settings.resultsFontSize = 16
        settings.dimColorHex = "#FF0000"

        let appearance = ResultsAppearance.current(settings: settings)
        #expect(appearance.fontSize == 16)
        #expect(appearance.font.pointSize == 16)
        #expect(appearance.rowHeight == 27)
        #expect(appearance.dimColor.hexString == "#FF0000")
    }

    @Test
    func clampsFontSizeAndFallsBackForInvalidColor() {
        #expect(ResultsAppearance(fontSize: 2, dimColorHex: "#A0A7B3").fontSize == ResultsAppearance.minimumFontSize)
        #expect(ResultsAppearance(fontSize: 99, dimColorHex: "#A0A7B3").fontSize == ResultsAppearance.maximumFontSize)
        #expect(ResultsAppearance(fontSize: 13, dimColorHex: "nope").dimColor == .tertiaryLabelColor)
        #expect(ResultsAppearance(fontSize: 13, dimColorHex: "#A0A7B3").rowHeight == 24)
        #expect(ResultsAppearance(fontSize: 13, dimColorHex: "#A0A7B3").listIconSize == 16)
        #expect(ResultsAppearance(fontSize: 16, dimColorHex: "#A0A7B3").listIconSize == 20)
    }

    @Test
    func invisibleItemsUseDimColor() {
        let appearance = ResultsAppearance(fontSize: 13, dimColorHex: "#00FF00")
        let visible = SearchResultItem(path: "/tmp/a.txt", matchReason: "", previewSnippet: nil)
        let hidden = SearchResultItem(path: "/tmp/.a", matchReason: "", previewSnippet: nil, isInvisible: true)

        #expect(appearance.textColor(for: visible) == .labelColor)
        #expect(appearance.textColor(for: hidden).hexString == "#00FF00")
    }

    @Test
    func settingsChangesPostNotification() {
        let settings = AppSettings(storage: InMemoryKeyValueStore())
        var count = 0
        let token = NotificationCenter.default.addObserver(
            forName: AppSettings.resultsAppearanceDidChangeNotification,
            object: settings,
            queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.resultsFontSize = 15
        settings.dimColorHex = "#123456"
        #expect(count == 2)
    }

    @MainActor
    @Test
    func tableControllerAppliesAppearanceToRowsAndNames() {
        let controller = ResultsTableViewController()
        _ = controller.view
        controller.applyResultsAppearance(ResultsAppearance(fontSize: 15, dimColorHex: "#112233"))

        #expect(controller.debugRowHeight == 26)
        let hidden = SearchResultItem(path: "/tmp/.hidden", matchReason: "", previewSnippet: nil, isInvisible: true)
        let attributes = controller.debugNameAttributes(for: hidden)
        #expect(attributes.font?.pointSize == 15)
        #expect(attributes.color?.hexString == "#112233")
    }

    @MainActor
    @Test
    func outlineControllerAppliesRowHeight() {
        let controller = ResultsOutlineViewController()
        _ = controller.view
        controller.applyResultsAppearance(ResultsAppearance(fontSize: 10, dimColorHex: "#112233"))
        #expect(controller.debugRowHeight == 21)
    }
}
