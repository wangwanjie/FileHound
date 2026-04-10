import AppKit
import Testing
@testable import FileHound

struct SearchWindowLayoutCoordinatorTests {
    @Test
    func expandsWindowUntilVisibleFrameLimitThenEnablesRuleScrolling() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        let coordinator = SearchWindowLayoutCoordinator(visibleFrameProvider: { visibleFrame })

        let compact = coordinator.layout(
            currentFrame: NSRect(x: 200, y: 300, width: 800, height: 236),
            desiredRuleContentHeight: 140,
            minimumRuleAreaHeight: 120,
            minimumWindowHeight: 236,
            chromeHeight: 120,
            maxWindowHeightFraction: 0.72
        )

        #expect(compact.shouldScrollRules == false)
        #expect(compact.frame.height >= 260)

        let oversized = coordinator.layout(
            currentFrame: NSRect(x: 200, y: 100, width: 800, height: 236),
            desiredRuleContentHeight: 520,
            minimumRuleAreaHeight: 120,
            minimumWindowHeight: 236,
            chromeHeight: 120,
            maxWindowHeightFraction: 0.72
        )

        #expect(oversized.frame.maxY == visibleFrame.maxY)
        #expect(oversized.shouldScrollRules == true)
        #expect(oversized.ruleAreaHeight < 520)
    }
}
