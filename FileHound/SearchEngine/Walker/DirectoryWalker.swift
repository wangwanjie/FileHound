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

/// 多线程遍历目录树：多个工作线程共享一个待列目录栈，各自列目录并回调子项。
/// visit 会在多个线程上并发调用，回调顺序不固定，但父目录条目总是先于其子项被回调。
struct DirectoryWalker: Sendable {
    /// 实测 8 个线程在 APFS SSD 上吞吐最高，再多反而因锁与 I/O 竞争变慢
    static let defaultConcurrency = min(max(ProcessInfo.processInfo.activeProcessorCount, 2), 8)

    private let providerFactory: @Sendable (ProviderKind) -> any FilesystemAccessProviding
    private let concurrency: Int

    init(
        providerFactory: @escaping @Sendable (ProviderKind) -> any FilesystemAccessProviding = { kind in
            switch kind {
            case .local:
                return LocalFilesystemProvider()
            case .privileged:
                return PrivilegedFilesystemProvider()
            }
        },
        concurrency: Int = DirectoryWalker.defaultConcurrency
    ) {
        self.providerFactory = providerFactory
        self.concurrency = max(concurrency, 1)
    }

    func walk(plan: SearchPlan, includeHiddenFiles: Bool) throws -> [DirectoryEntry] {
        let collected = LockedEntries()
        _ = try walk(plan: plan, includeHiddenFiles: includeHiddenFiles) { entry in
            collected.append(entry)
            return .continue
        }
        return collected.entries
    }

    /// 返回 false 表示遍历被 visit 的 .stop 或任务取消提前终止
    @discardableResult
    func walk(
        plan: SearchPlan,
        includeHiddenFiles: Bool,
        visit: @escaping @Sendable (DirectoryEntry) throws -> DirectoryWalkControl
    ) throws -> Bool {
        guard Task.isCancelled == false else {
            return false
        }

        let state = WalkState(rootPaths: plan.rootPaths)
        let context = WalkContext(
            provider: providerFactory(plan.providerKind),
            includeHiddenFiles: includeHiddenFiles,
            excludedPathFragments: plan.excludedPathFragments,
            specialFolderPlanning: plan.specialFolderPlanningResult,
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
            if Task.isCancelled {
                state.stop()
            }
        }

        if let error = state.error {
            throw error
        }
        return state.isStopped == false && Task.isCancelled == false
    }

    private static func runWorker(state: WalkState, context: WalkContext) {
        while let directoryPath = state.nextDirectory() {
            let subdirectories = listChildren(of: directoryPath, state: state, context: context)
            state.finish(directory: directoryPath, discovered: subdirectories)
        }
    }

    private static func listChildren(
        of path: String,
        state: WalkState,
        context: WalkContext
    ) -> [String] {
        let children: [DirectoryListingItem]
        do {
            children = try context.provider.listDirectory(atPath: path)
        } catch {
            return []
        }

        let prefix = path.hasSuffix("/") ? path : path + "/"
        var subdirectories: [String] = []
        // 停止标志只在取目录时检查，避免每个子项都争用共享锁
        for child in children {
            let childPath = prefix + child.name
            guard context.excludedPathFragments.isEmpty
                    || context.excludedPathFragments.contains(where: childPath.contains) == false else {
                continue
            }

            guard context.specialFolderPlanning.allows(path: childPath) else {
                continue
            }

            let entry = DirectoryEntry(
                path: childPath,
                isDirectory: child.isDirectory,
                isHidden: child.name.hasPrefix(".")
            )

            guard context.includeHiddenFiles || entry.isHidden == false else {
                continue
            }

            let control: DirectoryWalkControl
            do {
                control = try context.visit(entry)
            } catch {
                state.fail(with: error)
                break
            }

            if control == .stop {
                state.stop()
                break
            }

            if entry.isDirectory, control != .skipDescendants {
                subdirectories.append(childPath)
            }
        }
        return subdirectories
    }
}

private struct WalkContext: Sendable {
    let provider: any FilesystemAccessProviding
    let includeHiddenFiles: Bool
    let excludedPathFragments: Set<String>
    let specialFolderPlanning: SpecialFolderPlanningResult
    let visit: @Sendable (DirectoryEntry) throws -> DirectoryWalkControl
}

/// 共享的待遍历目录栈。outstanding 统计已入栈但尚未处理完的目录数，归零即遍历完成
private final class WalkState: @unchecked Sendable {
    private let condition = NSCondition()
    private var pendingDirectories: [String]
    private var outstandingCount: Int
    private var stopped = false
    private var firstError: Error?

    init(rootPaths: [String]) {
        // 栈顶先出，倒序入栈让第一个根目录最先被遍历
        pendingDirectories = rootPaths.reversed()
        outstandingCount = rootPaths.count
    }

    var isStopped: Bool {
        condition.lock()
        defer { condition.unlock() }
        return stopped
    }
    var error: Error? {
        condition.lock()
        defer { condition.unlock() }
        return firstError
    }

    /// 阻塞直到取到一个待列目录；遍历完成或已停止时返回 nil
    func nextDirectory() -> String? {
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

    func finish(directory: String, discovered subdirectories: [String]) {
        condition.lock()
        defer { condition.unlock() }
        guard stopped == false else {
            return
        }
        // 倒序入栈，使同一目录下的子目录按列出顺序被取出
        pendingDirectories.append(contentsOf: subdirectories.reversed())
        outstandingCount += subdirectories.count - 1
        if outstandingCount == 0 || subdirectories.isEmpty == false {
            condition.broadcast()
        }
    }

    func stop() {
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
    }

    func fail(with error: Error) {
        condition.lock()
        if firstError == nil {
            firstError = error
        }
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
