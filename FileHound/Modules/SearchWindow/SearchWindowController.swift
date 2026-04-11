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
    private static let defaultContentSize = NSSize(width: 760, height: 214)
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
        window.setContentSize(Self.defaultContentSize)
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
        window?.title = "FileHound"
        if let controller = window?.contentViewController as? SearchFormViewController {
            controller.reloadLocalizedStrings()
            searchFormViewController(controller, desiredRulesContentHeight: controller.preferredRulesContentHeight)
            return
        }

        let controller = SearchFormViewController()
        controller.windowLayoutDelegate = self
        window?.contentViewController = controller
        _ = controller.view
        searchFormViewController(controller, desiredRulesContentHeight: controller.preferredRulesContentHeight)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if let controller = window?.contentViewController as? SearchFormViewController {
            searchFormViewController(controller, desiredRulesContentHeight: controller.preferredRulesContentHeight)
        }
    }

    func apply(searchSessionSnapshot: SearchSessionSnapshot) {
        showWindow(nil)
        guard let controller = window?.contentViewController as? SearchFormViewController else {
            return
        }

        controller.applySearchSessionSnapshot(searchSessionSnapshot)
        searchFormViewController(controller, desiredRulesContentHeight: controller.preferredRulesContentHeight)
        window?.makeKeyAndOrderFront(nil)
    }

    func currentSearchSessionSnapshot() -> SearchSessionSnapshot? {
        guard let controller = window?.contentViewController as? SearchFormViewController else {
            return nil
        }

        return controller.currentSearchSessionSnapshot()
    }

    func searchFormViewController(_ controller: SearchFormViewController?, desiredRulesContentHeight: CGFloat) {
        guard let window, let controller else {
            return
        }

        let currentWindowFrame = window.frame
        let currentFrame = window.contentRect(forFrameRect: currentWindowFrame)
        let layout = layoutCoordinator.layout(
            currentFrame: currentFrame,
            desiredRuleContentHeight: desiredRulesContentHeight,
            minimumRuleAreaHeight: 78,
            minimumWindowHeight: Self.defaultContentSize.height,
            chromeHeight: 124,
            maxWindowHeightFraction: 1
        )

        controller.applyRuleAreaLayout(height: layout.ruleAreaHeight, shouldScroll: layout.shouldScrollRules)
        let nextFrame = window.frameRect(forContentRect: layout.frame)
        var preservedFrame = currentWindowFrame
        preservedFrame.origin.y = nextFrame.origin.y
        preservedFrame.size.height = nextFrame.size.height
        window.setFrame(preservedFrame, display: true)
    }
}
