import Foundation

enum DirectoryWalkControl {
    case `continue`
    /// 保留当前条目但不再进入其子目录
    case skipDescendants
    case stop
}

struct DirectoryEntry: Equatable, Sendable {
    let path: String
    let isDirectory: Bool
    let isHidden: Bool

    var lastPathComponent: String {
        (path as NSString).lastPathComponent
    }
}

/// 搜索的取消标志。搜索在专用线程和 GCD 工作线程上执行，不在 Swift 并发的任务上下文中，
/// Task.isCancelled 传递不过去，由调用方持有它并在停止时调用 cancel()
final class SearchCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let parent: SearchCancellationToken?

    /// parent 被取消时本标志也视为已取消，用于从整次搜索派生出可单独停止的阶段
    init(parent: SearchCancellationToken? = nil) {
        self.parent = parent
    }

    /// 已调用 cancel()、上级已取消，或当前线程所在的 Swift 任务已被取消
    var isCancelled: Bool {
        lock.lock()
        let flag = cancelled
        lock.unlock()
        return flag || parent?.isCancelled == true || Task.isCancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// 多线程遍历目录树：多个工作线程共享一个待列目录栈，各自列目录并回调子项。
/// visit 会在多个线程上并发调用，回调顺序不固定，但父目录条目总是先于其子项被回调。
/// 特殊文件夹中的“慢速搜索”目录延后遍历：其余目录全部遍历完之后才进入它们。
struct DirectoryWalker: Sendable {
    /// 实测 8 个线程在 APFS SSD 上吞吐最高，再多反而因锁与 I/O 竞争变慢
    static let defaultConcurrency = min(max(ProcessInfo.processInfo.activeProcessorCount, 2), 8)

    private let provider: any FilesystemAccessProviding
    private let concurrency: Int

    init(
        provider: any FilesystemAccessProviding = LocalFilesystemProvider(),
        concurrency: Int = DirectoryWalker.defaultConcurrency
    ) {
        self.provider = provider
        self.concurrency = max(concurrency, 1)
    }

    func walk(plan: SearchPlan, includeHiddenFiles: Bool) -> [DirectoryEntry] {
        let collected = LockedEntries()
        walk(plan: plan, includeHiddenFiles: includeHiddenFiles) { entry in
            collected.append(entry)
            return .continue
        }
        return collected.entries
    }

    /// 返回 false 表示遍历被 visit 的 .stop 或取消提前终止
    @discardableResult
    func walk(
        plan: SearchPlan,
        includeHiddenFiles: Bool,
        cancellation: SearchCancellationToken? = nil,
        visit: @escaping @Sendable (DirectoryEntry) -> DirectoryWalkControl
    ) -> Bool {
        let isCancelled = { Task.isCancelled || cancellation?.isCancelled == true }
        guard isCancelled() == false else {
            return false
        }

        let normalizedRoots = plan.rootPaths.map(Self.trimmingTrailingSlash)
        // 工作线程每取一个目录前也检查取消标志，不必等调用线程下一次轮询
        let state = WalkState(rootPaths: plan.rootPaths, isCancelled: { cancellation?.isCancelled == true })
        let context = WalkContext(
            provider: provider,
            includeHiddenFiles: includeHiddenFiles,
            specialFolderPlanning: plan.specialFolderPlanning,
            // 嵌套的搜索根各自单独遍历，外层根遍历到它时不再进入，避免同一棵子树被遍历两次
            nestedRoots: normalizedRoots.count > 1 ? Set(normalizedRoots) : [],
            visit: visit
        )

        let group = DispatchGroup()
        for _ in 0..<concurrency {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                Self.runWorker(state: state, context: context)
                group.leave()
            }
        }

        // 工作线程不在 Task 上下文中，取消状态由调用线程轮询后转发
        while group.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if isCancelled() {
                state.stop()
            }
        }

        return state.isStopped == false && isCancelled() == false
    }

    private static func runWorker(state: WalkState, context: WalkContext) {
        while let directory = state.nextDirectory() {
            let discovered = listChildren(of: directory, state: state, context: context)
            state.finish(discovered: discovered.immediate, deferred: discovered.deferred)
        }
    }

    private static func listChildren(
        of directory: PendingDirectory,
        state: WalkState,
        context: WalkContext
    ) -> (immediate: [PendingDirectory], deferred: [PendingDirectory]) {
        let children: [DirectoryListingItem]
        do {
            children = try context.provider.listDirectory(atPath: directory.path)
        } catch {
            return ([], [])
        }

        let planning = context.specialFolderPlanning[directory.rootIndex]
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        var subdirectories: [PendingDirectory] = []
        var deferredDirectories: [PendingDirectory] = []
        // 停止标志只在取目录时检查，避免每个子项都争用共享锁
        for child in children {
            let childPath = prefix + child.name
            guard planning.allows(path: childPath) else {
                continue
            }

            let entry = DirectoryEntry(
                path: childPath,
                isDirectory: child.isDirectory,
                isHidden: child.isHidden
            )

            guard context.includeHiddenFiles || entry.isHidden == false else {
                continue
            }

            let control = context.visit(entry)
            if control == .stop {
                state.stop()
                break
            }

            guard entry.isDirectory, control != .skipDescendants else {
                continue
            }
            if context.nestedRoots.isEmpty == false, context.nestedRoots.contains(childPath) {
                continue
            }
            let pending = PendingDirectory(path: childPath, rootIndex: directory.rootIndex)
            if planning.isSlowSearchPath(childPath) {
                deferredDirectories.append(pending)
            } else {
                subdirectories.append(pending)
            }
        }
        return (subdirectories, deferredDirectories)
    }

    private static func trimmingTrailingSlash(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}

/// 待列出的目录及其所属搜索根的下标，用来取该根自己的特殊文件夹规划
private struct PendingDirectory: Sendable {
    let path: String
    let rootIndex: Int
}

private struct WalkContext: Sendable {
    let provider: any FilesystemAccessProviding
    let includeHiddenFiles: Bool
    let specialFolderPlanning: [SpecialFolderPlanningResult]
    let nestedRoots: Set<String>
    let visit: @Sendable (DirectoryEntry) -> DirectoryWalkControl
}

/// 共享的待遍历目录栈。outstanding 统计已入栈但尚未处理完的目录数；
/// 归零时若还有延后的慢速目录就把它们放回栈中继续，否则遍历完成
private final class WalkState: @unchecked Sendable {
    private let condition = NSCondition()
    private var pendingDirectories: [PendingDirectory]
    private var deferredDirectories: [PendingDirectory] = []
    private var outstandingCount: Int
    private var stopped = false
    private let isCancelled: @Sendable () -> Bool

    init(rootPaths: [String], isCancelled: @escaping @Sendable () -> Bool) {
        self.isCancelled = isCancelled
        // 栈顶先出，倒序入栈让第一个根目录最先被遍历
        pendingDirectories = rootPaths.enumerated()
            .map { PendingDirectory(path: $0.element, rootIndex: $0.offset) }
            .reversed()
        outstandingCount = rootPaths.count
    }

    var isStopped: Bool {
        condition.lock()
        defer { condition.unlock() }
        return stopped
    }

    /// 阻塞直到取到一个待列目录；遍历完成或已停止时返回 nil
    func nextDirectory() -> PendingDirectory? {
        if isCancelled() {
            stop()
            return nil
        }
        condition.lock()
        defer { condition.unlock() }
        while pendingDirectories.isEmpty, outstandingCount > 0, stopped == false {
            condition.wait()
        }
        guard stopped == false else {
            return nil
        }
        return pendingDirectories.popLast()
    }

    func finish(discovered subdirectories: [PendingDirectory], deferred: [PendingDirectory]) {
        condition.lock()
        defer { condition.unlock() }
        guard stopped == false else {
            return
        }
        // 倒序入栈，使同一目录下的子目录按列出顺序被取出
        pendingDirectories.append(contentsOf: subdirectories.reversed())
        deferredDirectories.append(contentsOf: deferred)
        outstandingCount += subdirectories.count - 1

        var releasedDeferred = false
        if outstandingCount == 0, deferredDirectories.isEmpty == false {
            // 其余目录都已遍历完，开始遍历延后的慢速目录；其中再遇到的慢速目录会在下一轮继续延后
            pendingDirectories = deferredDirectories.reversed()
            outstandingCount = deferredDirectories.count
            deferredDirectories = []
            releasedDeferred = true
        }
        if outstandingCount == 0 || subdirectories.isEmpty == false || releasedDeferred {
            condition.broadcast()
        }
    }

    func stop() {
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class LockedEntries: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DirectoryEntry] = []

    var entries: [DirectoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ entry: DirectoryEntry) {
        lock.lock()
        storage.append(entry)
        lock.unlock()
    }
}
