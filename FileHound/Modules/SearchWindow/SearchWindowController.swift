//
//  SearchWindowController.swift
//  FileHound
//
//  Created by VanJay on 2026/4/8.
//

import AppKit

protocol SearchWindowLayoutDelegate: AnyObject {
    func searchFormViewController(_ controller: SearchFormViewController?, desiredRulesContentHeight: CGFloat)
}

final class SearchWindowController: NSWindowController, SearchWindowLayoutDelegate {
    private let layoutCoordinator: SearchWindowLayoutCoordinator

    init(
        layoutCoordinator: SearchWindowLayoutCoordinator = SearchWindowLayoutCoordinator(
            visibleFrameProvider: { NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720) }
        )
    ) {
        self.layoutCoordinator = layoutCoordinator
        super.init(window: nil)
    }

    convenience init() {
        self.init(layoutCoordinator: SearchWindowLayoutCoordinator(
            visibleFrameProvider: { NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720) }
        ))
        let formController = SearchFormViewController()
        formController.windowLayoutDelegate = self
        let window = NSWindow(contentViewController: formController)
        window.title = "FileHound"
        window.setContentSize(NSSize(width: 800, height: 236))
        window.center()
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        self.window = window
        _ = formController.view
        searchFormViewController(formController, desiredRulesContentHeight: formController.preferredRulesContentHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadLocalizedContent() {
        let controller = SearchFormViewController()
        controller.windowLayoutDelegate = self
        window?.contentViewController = controller
        window?.title = "FileHound"
        _ = controller.view
        searchFormViewController(controller, desiredRulesContentHeight: controller.preferredRulesContentHeight)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if let controller = window?.contentViewController as? SearchFormViewController {
            searchFormViewController(controller, desiredRulesContentHeight: controller.preferredRulesContentHeight)
        }
    }

    func searchFormViewController(_ controller: SearchFormViewController?, desiredRulesContentHeight: CGFloat) {
        guard let window, let controller else {
            return
        }

        let currentFrame = window.contentRect(forFrameRect: window.frame)
        let layout = layoutCoordinator.layout(
            currentFrame: currentFrame,
            desiredRuleContentHeight: desiredRulesContentHeight,
            minimumRuleAreaHeight: 120,
            minimumWindowHeight: 236,
            chromeHeight: 120,
            maxWindowHeightFraction: 0.72
        )

        controller.applyRuleAreaLayout(height: layout.ruleAreaHeight, shouldScroll: layout.shouldScrollRules)
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: layout.frame.size)).size
        let titlebarDelta = frameSize.height - layout.frame.size.height
        let nextFrame = NSRect(
            x: window.frame.origin.x,
            y: layout.frame.origin.y - titlebarDelta,
            width: frameSize.width,
            height: frameSize.height
        )
        window.setFrame(nextFrame, display: true)
    }
}
