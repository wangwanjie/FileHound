import AppKit

struct SearchWindowLayout {
    let frame: NSRect
    let ruleAreaHeight: CGFloat
    let shouldScrollRules: Bool
}

struct SearchWindowLayoutCoordinator {
    var visibleFrameProvider: () -> NSRect

    func layout(
        currentFrame: NSRect,
        desiredRuleContentHeight: CGFloat,
        minimumRuleAreaHeight: CGFloat,
        minimumWindowHeight: CGFloat,
        chromeHeight: CGFloat,
        maxWindowHeightFraction: CGFloat
    ) -> SearchWindowLayout {
        let visibleFrame = visibleFrameProvider()
        let maxAllowedHeight = min(visibleFrame.height, visibleFrame.height * maxWindowHeightFraction)
        let desiredRuleAreaHeight = max(minimumRuleAreaHeight, desiredRuleContentHeight)
        let desiredWindowHeight = max(minimumWindowHeight, chromeHeight + desiredRuleAreaHeight)
        let finalWindowHeight = min(maxAllowedHeight, desiredWindowHeight)
        let shouldScrollRules = desiredWindowHeight > maxAllowedHeight
        let finalRuleAreaHeight = max(minimumRuleAreaHeight, finalWindowHeight - chromeHeight)

        let defaultOriginY = currentFrame.origin.y
        let needsTopAlignment = currentFrame.maxY > visibleFrame.maxY || shouldScrollRules
        let alignedOriginY = needsTopAlignment
            ? visibleFrame.maxY - finalWindowHeight
            : defaultOriginY
        let finalOriginY = max(visibleFrame.minY, alignedOriginY)

        return SearchWindowLayout(
            frame: NSRect(
                x: currentFrame.origin.x,
                y: finalOriginY,
                width: currentFrame.width,
                height: finalWindowHeight
            ),
            ruleAreaHeight: finalRuleAreaHeight,
            shouldScrollRules: shouldScrollRules
        )
    }
}
