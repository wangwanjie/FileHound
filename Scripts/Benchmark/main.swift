// FileHound 搜索引擎基准测试。
// 由 Scripts/benchmark.sh 与 App 的搜索引擎源码（DirectoryWalker、BulkDirectoryLister、
// LocalVolumeCatalogSearcher、ContentMatcher 等）一起用 -O 编译，测的是与 App 相同的实现，
// 并与 find / grep / ripgrep / mdfind 及朴素的 Foundation 实现对比。

import Darwin
import Foundation

// MARK: - 编译引擎源码所需的最小替身

/// SearchRuleCatalog 中的显示文案依赖本地化模块，基准测试不需要
enum L10n {
    static func string(_ key: String) -> String { key }
}

/// SpecialFolderPlanner 只用到规则的路径与处理方式；完整定义在偏好模型中，牵连主题、更新等设置
enum SpecialFolderDisposition {
    case include
    case exclude
    case slowSearch
}

struct SpecialFolderRule {
    var path: String
    var disposition: SpecialFolderDisposition
}

struct SpecialFoldersConfiguration {
    var rules: [SpecialFolderRule] = []
}

// MARK: - 参数

struct Options {
    var treeRoot = "/System/Library"
    var nameQuery = "plist"
    var contentRoot = ""
    var contentQuery = "kCFAllocatorDefault"
    var runs = 5
    var includeVolume = true

    static func parse() -> Options {
        var options = Options()
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--tree-root": options.treeRoot = arguments.next() ?? options.treeRoot
            case "--name": options.nameQuery = arguments.next() ?? options.nameQuery
            case "--content-root": options.contentRoot = arguments.next() ?? options.contentRoot
            case "--content": options.contentQuery = arguments.next() ?? options.contentQuery
            case "--runs": options.runs = max(Int(arguments.next() ?? "") ?? options.runs, 1)
            case "--skip-volume": options.includeVolume = false
            default:
                FileHandle.standardError.write("未知参数：\(argument)\n".data(using: .utf8)!)
                exit(2)
            }
        }
        return options
    }
}

// MARK: - 计时与报告

struct Measurement {
    let name: String
    let note: String
    let seconds: [Double]
    let resultCount: Int

    var median: Double {
        let sorted = seconds.sorted()
        return sorted[sorted.count / 2]
    }
}

/// 先跑一次预热（让各实现都在目录缓存已热的条件下比较），再取 runs 次的中位数。
/// 预热就超过 slowThreshold 秒的朴素实现只计这一次，避免整个基准测试跑上十几分钟
let slowThreshold: Double = 10

func measure(_ name: String, note: String = "", runs: Int, _ body: () -> Int) -> Measurement {
    log("  · \(name) …")
    func timed() -> (Double, Int) {
        let start = DispatchTime.now().uptimeNanoseconds
        let count = body()
        return (Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9, count)
    }
    let (warmupSeconds, warmupCount) = timed()
    var seconds: [Double] = []
    var count = warmupCount
    if warmupSeconds > slowThreshold {
        seconds = [warmupSeconds]
    } else {
        for _ in 0..<runs {
            let (elapsed, runCount) = timed()
            seconds.append(elapsed)
            count = runCount
        }
    }
    let result = Measurement(name: name, note: note, seconds: seconds, resultCount: count)
    log(String(format: "    %.3fs，%d 个结果", result.median, count))
    return result
}

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func printTable(title: String, subtitle: String, measurements: [Measurement], baselineName: String) {
    let baseline = measurements.first { $0.name == baselineName }?.median
    let fullCount = measurements.map(\.resultCount).max() ?? 0
    print("### \(title)\n")
    print("\(subtitle)\n")
    print("| 实现 | 耗时（中位数） | 相对 \(baselineName) | 结果数 | 说明 |")
    print("| --- | ---: | ---: | ---: | --- |")
    for measurement in measurements {
        // 结果明显不全（如 Spotlight 未索引该目录）时速度没有可比性
        let isIncomplete = Double(measurement.resultCount) < Double(fullCount) * 0.9
        let ratio = isIncomplete ? "不可比" : baseline.map { String(format: "%.1f×", $0 / measurement.median) } ?? "—"
        let note = isIncomplete ? measurement.note + "；**结果不全**" : measurement.note
        print(String(format: "| %@ | %.3f s | %@ | %d | %@ |",
                     measurement.name, measurement.median, ratio, measurement.resultCount, note))
    }
    print("")
}

/// 运行外部命令并统计标准输出行数（即匹配的路径数），标准错误（无权限等）丢弃
func countOutputLines(_ executable: String, _ arguments: [String]) -> Int {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return -1
    }
    var lines = 0
    let handle = pipe.fileHandleForReading
    while true {
        let chunk = handle.availableData
        if chunk.isEmpty { break }
        lines += chunk.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
    }
    process.waitUntilExit()
    return lines
}

func executablePath(_ name: String) -> String? {
    for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
        let path = directory + "/" + name
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }
    return nil
}

// MARK: - 名称匹配（与 App 默认的“名称包含”一致：忽略大小写与变音符号）

let nameCompareOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// 不覆盖 listDirectory，使用协议默认实现：contentsOfDirectory 列名后逐项 attributesOfItem（每项一次 stat）
struct NaiveFilesystemProvider: FilesystemAccessProviding {
    let kind: ProviderKind = .local
    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }
    func contentsOfFile(atPath path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }
}

func walkerNameSearch(
    roots: [String],
    query: String,
    concurrency: Int,
    provider: @escaping @Sendable () -> any FilesystemAccessProviding = { LocalFilesystemProvider() },
    skipping skippedPaths: Set<String> = []
) -> Int {
    let walker = DirectoryWalker(providerFactory: { _ in provider() }, concurrency: concurrency)
    let plan = SearchPlan(rootPaths: roots, rootGroup: .all([]), excludedPathFragments: [], providerKind: .local, shouldScanContents: false)
    let matches = Counter()
    _ = try? walker.walk(plan: plan, includeHiddenFiles: true) { entry in
        if skippedPaths.contains(entry.path) {
            return .skipDescendants
        }
        // 查询为空时统计全部条目
        if query.isEmpty || entry.lastPathComponent.range(of: query, options: nameCompareOptions) != nil {
            matches.increment()
        }
        return .continue
    }
    return matches.count
}

func foundationEnumeratorNameSearch(root: String, query: String) -> Int {
    guard let enumerator = FileManager.default.enumerator(atPath: root) else {
        return 0
    }
    var matches = 0
    while let relativePath = enumerator.nextObject() as? String {
        if (relativePath as NSString).lastPathComponent.range(of: query, options: nameCompareOptions) != nil {
            matches += 1
        }
    }
    return matches
}

// MARK: - 场景

let options = Options.parse()
let cpuName: String = {
    var size = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
    return String(cString: buffer)
}()
let memoryGB = ProcessInfo.processInfo.physicalMemory >> 30
let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

print("## Benchmark 结果\n")
print("- 机器：\(cpuName)，\(ProcessInfo.processInfo.activeProcessorCount) 核，\(memoryGB) GB 内存")
print("- 系统：macOS \(osVersion)")
print("- 方法：每个实现先预热 1 次，再取 \(options.runs) 次的中位数（目录与文件缓存均已热，预热超过 \(Int(slowThreshold)) 秒的只计 1 次）；FileHound 各项由 App 引擎源码以 `-O` 编译\n")

// 场景一：在一棵目录树中按名称搜索
do {
    let root = options.treeRoot
    let query = options.nameQuery
    log("场景一：在 \(root) 中按名称搜索 “\(query)”")
    var results: [Measurement] = []
    results.append(measure("`find -iname`", note: "BSD find，单线程 fts + stat", runs: options.runs) {
        countOutputLines("/usr/bin/find", [root, "-iname", "*\(query)*"])
    })
    results.append(measure("FileManager.enumerator", note: "Foundation 朴素实现，单线程", runs: options.runs) {
        foundationEnumeratorNameSearch(root: root, query: query)
    })
    results.append(measure("列名 + 逐项读属性", note: "同一个 DirectoryWalker 单线程，但用 contentsOfDirectory + attributesOfItem 代替 getattrlistbulk", runs: options.runs) {
        walkerNameSearch(roots: [root], query: query, concurrency: 1, provider: { NaiveFilesystemProvider() })
    })
    results.append(measure("FileHound 单线程", note: "getattrlistbulk 批量列目录", runs: options.runs) {
        walkerNameSearch(roots: [root], query: query, concurrency: 1)
    })
    results.append(measure("**FileHound（App 默认）**", note: "getattrlistbulk + \(DirectoryWalker.defaultConcurrency) 线程共享目录栈", runs: options.runs) {
        walkerNameSearch(roots: [root], query: query, concurrency: DirectoryWalker.defaultConcurrency)
    })
    results.append(measure("`mdfind -onlyin`", note: "Spotlight 索引，仅含已索引条目", runs: options.runs) {
        countOutputLines("/usr/bin/mdfind", ["-onlyin", root, "kMDItemFSName == '*\(query)*'cd"])
    })
    let entryCount = walkerNameSearch(roots: [root], query: "", concurrency: DirectoryWalker.defaultConcurrency)
    printTable(
        title: "场景一：目录树按名称搜索",
        subtitle: "在 `\(root)`（共 \(entryCount) 个条目）中查找名称包含 `\(query)` 的文件和文件夹（忽略大小写）。",
        measurements: results,
        baselineName: "`find -iname`"
    )
}

// 场景二：整个启动卷按名称搜索
if options.includeVolume {
    let query = options.nameQuery
    log("场景二：整个启动卷按名称搜索 “\(query)”")
    let searcher = LocalVolumeCatalogSearcher()
    // 与 App “启动卷”范围一致（SearchScopeResolver.startupVolumeExclusions）：不进入其他卷宗挂载点、
    // Data 卷的原始挂载路径（同一批文件已经经由固件链接出现在 /Users 等位置）、设备文件与自动挂载点
    let excluded = ["/Volumes", "/System/Volumes", "/dev", "/private/var/vm", "/.vol", "/Network", "/net"]
    func isExcluded(_ path: String) -> Bool {
        excluded.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
    // 与 SearchExecutor.catalogSearchPlan 一致：启动卷 + Data 卷 + 遍历会进入的嵌套卷（如 cryptex 挂载点），并发搜索
    let mountPoints = searcher.mountPoints()
    let volumes = ["/", "/System/Volumes/Data"].filter(mountPoints.contains)
        + mountPoints.filter { $0 != "/" && $0.hasPrefix("/") && isExcluded($0) == false }.sorted()
    var results: [Measurement] = []

    results.append(measure("FileHound 遍历", note: "getattrlistbulk + \(DirectoryWalker.defaultConcurrency) 线程，从 / 逐目录列出", runs: options.runs) {
        walkerNameSearch(roots: ["/"], query: query, concurrency: DirectoryWalker.defaultConcurrency, skipping: Set(excluded))
    })
    results.append(measure("**FileHound 卷目录搜索（App 默认）**", note: "searchfs 并发扫描 \(volumes.count) 个卷的目录（启动卷、Data 卷与嵌套卷），fsgetpath 还原路径", runs: options.runs) {
        let counter = Counter()
        let group = DispatchGroup()
        for volume in volumes {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                try? searcher.search(volumePath: volume, nameFragment: query, shouldStop: { false }) { matches in
                    for match in matches where isExcluded(match.path) == false {
                        counter.increment()
                    }
                }
            }
        }
        group.wait()
        return counter.count
    })
    results.append(measure("`mdfind -name`", note: "Spotlight 索引，仅含已索引条目", runs: options.runs) {
        countOutputLines("/usr/bin/mdfind", ["-name", query])
    })
    var volumeInfo = statfs()
    let usedInodes = volumes.prefix(2).reduce(UInt64(0)) { total, volume in
        statfs(volume, &volumeInfo) == 0 ? total + volumeInfo.f_files - volumeInfo.f_ffree : total
    }
    printTable(
        title: "场景二：整个启动卷按名称搜索",
        subtitle: "在启动卷（System + Data 卷约 \(usedInodes / 10_000) 万个文件系统对象，另有 \(volumes.count - 2) 个嵌套卷）中查找名称包含 `\(query)` 的条目。"
            + "两者结果集不完全相同：遍历进不了当前进程无权访问的目录；卷目录搜索对有多个硬链接的文件只返回一个路径。",
        measurements: results,
        baselineName: "FileHound 遍历"
    )
}

// 场景三：按文本内容搜索
do {
    let root = options.contentRoot
    let query = options.contentQuery
    var isDirectory: ObjCBool = false
    if root.isEmpty == false, FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue {
        log("场景三：在 \(root) 中按内容搜索 “\(query)”")
        var results: [Measurement] = []
        results.append(measure("`grep -rlF`", note: "BSD grep，单线程", runs: options.runs) {
            countOutputLines("/usr/bin/grep", ["-rlF", query, root])
        })
        if let ripgrep = executablePath("rg") {
            results.append(measure("`rg -l -F -uuu`", note: "ripgrep，多线程，不跳过任何文件", runs: options.runs) {
                countOutputLines(ripgrep, ["-l", "-F", "-uuu", query, root])
            })
        }

        let rule = SearchRuleSelection(field: .textContent, operator: .contains, value: query)
        results.append(measure("**FileHound（App 默认）**", note: "\(DirectoryWalker.defaultConcurrency) 线程遍历 + pread/mmap + memmem 字节预筛；会读取指向文件的符号链接，grep / rg 默认跳过", runs: options.runs) {
            let walker = DirectoryWalker()
            let provider = LocalFilesystemProvider()
            let matcher = ContentMatcher()
            let plan = SearchPlan(rootPaths: [root], rootGroup: .all([]), excludedPathFragments: [], providerKind: .local, shouldScanContents: true)
            let matches = Counter()
            _ = try? walker.walk(plan: plan, includeHiddenFiles: true) { entry in
                guard entry.isDirectory == false,
                      let data = try? provider.contentsOfFile(atPath: entry.path),
                      (try? matcher.matches(data: data, rule: rule, compareOptions: [], caseSensitive: true)) == true else {
                    return .continue
                }
                matches.increment()
                return .continue
            }
            return matches.count
        })
        let fileCount = walkerNameSearch(roots: [root], query: "", concurrency: DirectoryWalker.defaultConcurrency)
        printTable(
            title: "场景三：按文本内容搜索",
            subtitle: "在 `\(root)`（共 \(fileCount) 个条目）中查找内容包含 `\(query)` 的文件（区分大小写，跳过 Spotlight，逐个读取文件）。",
            measurements: results,
            baselineName: "`grep -rlF`"
        )
    } else {
        log("跳过场景三：未找到内容搜索目录（可用 --content-root 指定）")
    }
}
