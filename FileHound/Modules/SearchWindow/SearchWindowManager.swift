//
//  SearchWindowManager.swift
//  FileHound
//
//  Created by VanJay on 2026/10/2.
//

import AppKit

/// 管理多个查找窗口：⌘N 新建独立窗口，每个窗口各自持有搜索任务与结果窗口，互不覆盖。
final class SearchWindowManager {
    private(set) var controllers: [SearchWindowController] = []
    private let makeController: (_ restoresPreviousSession: Bool) -> SearchWindowController
    private let orderedWindowsProvider: () -> [NSWindow]
    /// 新窗口创建后回调，用于套用主题等
    var onControllerCreated: ((SearchWindowController) -> Void)?

    init(
        makeController: @escaping (_ restoresPreviousSession: Bool) -> SearchWindowController = {
            SearchWindowController(restoresPreviousSession: $0)
        },
        orderedWindowsProvider: @escaping () -> [NSWindow] = { NSApp.orderedWindows }
    ) {
        self.makeController = makeController
        self.orderedWindowsProvider = orderedWindowsProvider
    }

    var windows: [NSWindow] {
        controllers.compactMap(\.window)
    }

    /// 当前活跃的查找窗口：按窗口层级从前往后，取第一个拥有该窗口（查找窗口本身或它的结果窗口）的控制器
    var activeController: SearchWindowController? {
        for window in orderedWindowsProvider() {
            if let controller = controllers.first(where: { $0.owns(window: window) }) {
                return controller
            }
        }
        return controllers.last(where: \.isWindowOpen) ?? controllers.last
    }

    /// 显示当前活跃的查找窗口（启动、全局快捷键、点击 Dock 图标），没有时才新建
    @discardableResult
    func presentActiveWindow() -> SearchWindowController {
        let controller = activeController ?? register(makeController(true))
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return controller
    }

    /// 新建一个空白查找窗口（⌘N），相对当前窗口层叠摆放，原有窗口及其结果保持不变
    @discardableResult
    func openNewWindow() -> SearchWindowController {
        let anchorWindow = activeController.flatMap { $0.isWindowOpen ? $0.window : nil }
        releaseClosedControllers()

        let controller = register(makeController(false))
        if let anchorWindow, let window = controller.window {
            let anchorTopLeft = NSPoint(x: anchorWindow.frame.minX, y: anchorWindow.frame.maxY)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: anchorTopLeft))
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return controller
    }

    /// 打开最近 / 已存储搜索时的目标窗口：活跃窗口正在搜索时另开新窗口，避免打断进行中的搜索
    func controllerForApplyingSnapshot() -> SearchWindowController {
        if let controller = activeController, controller.isSearching == false {
            return controller
        }
        if controllers.contains(where: \.isWindowOpen) {
            return openNewWindow()
        }
        return register(makeController(true))
    }

    func reloadLocalizedContent() {
        controllers.forEach { $0.reloadLocalizedContent() }
    }

    @discardableResult
    private func register(_ controller: SearchWindowController) -> SearchWindowController {
        controller.onWindowWillClose = { [weak self] closingController in
            self?.windowWillClose(closingController)
        }
        controllers.append(controller)
        onControllerCreated?(controller)
        return controller
    }

    /// 仍有其他查找窗口打开时释放被关闭的窗口；最后一个窗口保留，点击 Dock 图标时原样恢复
    private func windowWillClose(_ controller: SearchWindowController) {
        let hasOtherOpenWindows = controllers.contains { $0 !== controller && $0.isWindowOpen }
        guard hasOtherOpenWindows else {
            return
        }
        release(controller)
    }

    /// 新建窗口前清理已关闭且空闲的查找窗口，避免关闭后保留的窗口不断累积
    private func releaseClosedControllers() {
        controllers
            .filter { $0.isWindowOpen == false && $0.isSearching == false }
            .forEach(release)
    }

    private func release(_ controller: SearchWindowController) {
        controller.cancelSearchIfNeeded()
        controller.onWindowWillClose = nil
        controllers.removeAll { $0 === controller }
    }
}
