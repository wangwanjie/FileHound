import AppKit
import Testing
@testable import FileHound

struct SearchWindowLayoutCoordinatorTests {
    @Test
    func keepsTopFixedWhileGrowingWhenThereIsRoomBelow() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        let coordinator = SearchWindowLayoutCoordinator(visibleFrameProvider: { visibleFrame })

        let expanded = coordinator.layout(
            currentFrame: NSRect(x: 200, y: 300, width: 800, height: 236),
            desiredRuleContentHeight: 220,
            minimumRuleAreaHeight: 120,
            minimumWindowHeight: 236,
            chromeHeight: 120,
            maxWindowHeightFraction: 1
        )

        #expect(expanded.shouldScrollRules == false)
        #expect(expanded.frame.maxY == 536)
        #expect(expanded.frame.minY < 300)
        #expect(expanded.frame.height == 340)
    }

    @Test
    func keepsBottomPinnedAndMovesWindowUpWhenGrowthWouldOverflowBelow() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        let coordinator = SearchWindowLayoutCoordinator(visibleFrameProvider: { visibleFrame })

        let expanded = coordinator.layout(
            currentFrame: NSRect(x: 200, y: 100, width: 800, height: 236),
            desiredRuleContentHeight: 520,
            minimumRuleAreaHeight: 120,
            minimumWindowHeight: 236,
            chromeHeight: 120,
            maxWindowHeightFraction: 1
        )

        #expect(expanded.shouldScrollRules == false)
        #expect(expanded.frame.minY == visibleFrame.minY)
        #expect(expanded.frame.height == 640)
        #expect(expanded.frame.maxY == 640)
    }

    @Test
    func enablesRuleScrollingOnlyAfterBothEdgesAreConstrained() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        let coordinator = SearchWindowLayoutCoordinator(visibleFrameProvider: { visibleFrame })

        let oversized = coordinator.layout(
            currentFrame: NSRect(x: 200, y: 100, width: 800, height: 236),
            desiredRuleContentHeight: 760,
            minimumRuleAreaHeight: 120,
            minimumWindowHeight: 236,
            chromeHeight: 120,
            maxWindowHeightFraction: 1
        )

        #expect(oversized.frame.minY == visibleFrame.minY)
        #expect(oversized.frame.maxY == visibleFrame.maxY)
        #expect(oversized.shouldScrollRules == true)
        #expect(oversized.ruleAreaHeight < 760)
    }

    @Test
    func keepsTopFixedWhileShrinkingAndMovesBottomUp() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        let coordinator = SearchWindowLayoutCoordinator(visibleFrameProvider: { visibleFrame })

        let compacted = coordinator.layout(
            currentFrame: NSRect(x: 200, y: 0, width: 800, height: 640),
            desiredRuleContentHeight: 200,
            minimumRuleAreaHeight: 120,
            minimumWindowHeight: 236,
            chromeHeight: 120,
            maxWindowHeightFraction: 1
        )

        #expect(compacted.shouldScrollRules == false)
        #expect(compacted.frame.maxY == 640)
        #expect(compacted.frame.minY == 320)
        #expect(compacted.frame.height == 320)
    }
}
