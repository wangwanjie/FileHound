import Darwin
import Foundation

struct VolumeCatalogMatch: Equatable, Sendable {
    let path: String
    let isDirectory: Bool
}

enum VolumeCatalogSearchError: Error {
    /// 卷不支持 searchfs（如网络卷、FAT），或首次调用即失败
    case unsupported(errno: Int32)
    /// 搜索中途失败，已回调的部分结果仍然有效
    case interrupted(errno: Int32)
}

/// 按文件名片段在整个卷的目录中查找。实现必须返回“名称包含该片段（不区分大小写与变音符号）”的条目的超集，
/// 调用方会按完整规则复核每个结果
protocol VolumeCatalogSearching: Sendable {
    /// 当前所有挂载点路径
    func mountPoints() -> [String]
    /// shouldStop 返回 true 时尽快结束并正常返回
    func search(
        volumePath: String,
        nameFragment: String,
        shouldStop: () -> Bool,
        onMatches: ([VolumeCatalogMatch]) -> Void
    ) throws
}

/// 用 searchfs 直接扫描卷的目录 B 树，不需要逐个目录打开、列出，整卷按名称搜索比遍历快得多。
/// 匹配不区分大小写，片段中不含变音符号时也能命中带变音符号的名称；不跨越挂载点，也不经过固件链接
struct LocalVolumeCatalogSearcher: VolumeCatalogSearching {
    private static let bufferSize = 256 * 1024
    private static let maximumMatchesPerCall = 4096
    /// 每次调用最多在内核中停留的时长，到时返回已找到的结果，便于分批展示和响应取消
    private static let timeLimitMicroseconds: Int32 = 200_000
    /// 内核按 UTF-8 解释名称参数（与 Finder / Find Any File 使用的取值一致）
    private static let utf8ScriptCode: UInt32 = 0x0800_0103
    /// 卷在搜索期间持续写入时，续搜会因目录变化失败，最多从头重来这么多次
    private static let maximumRestarts = 3

    init() {}

    func mountPoints() -> [String] {
        var mounts: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mounts, MNT_NOWAIT)
        guard count > 0, let mounts else {
            return []
        }
        return (0..<Int(count)).map { index in
            withUnsafeBytes(of: mounts[index].f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        }
    }

    func search(
        volumePath: String,
        nameFragment: String,
        shouldStop: () -> Bool,
        onMatches: ([VolumeCatalogMatch]) -> Void
    ) throws {
        var volumeInfo = statfs()
        guard statfs(volumePath, &volumeInfo) == 0 else {
            throw VolumeCatalogSearchError.unsupported(errno: errno)
        }
        var volumeID = volumeInfo.f_fsid

        // 名称参数：u_int32_t 总长度 + attrreference_t + 以 NUL 结尾的 UTF-8 名称
        let nameBytes = Array(nameFragment.utf8) + [0]
        let headerSize = MemoryLayout<UInt32>.size + MemoryLayout<attrreference_t>.size
        let parameterSize = headerSize + nameBytes.count
        let parameters = UnsafeMutableRawPointer.allocate(byteCount: parameterSize, alignment: 8)
        defer { parameters.deallocate() }
        parameters.storeBytes(of: UInt32(parameterSize), as: UInt32.self)
        var nameReference = attrreference_t()
        nameReference.attr_dataoffset = Int32(MemoryLayout<attrreference_t>.size)
        nameReference.attr_length = UInt32(nameBytes.count)
        withUnsafeBytes(of: nameReference) { (parameters + MemoryLayout<UInt32>.size).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        nameBytes.withUnsafeBytes { (parameters + headerSize).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        // fssearchblock 只保存指针，返回属性列表需要在整个搜索期间保持有效
        let returnAttributes = UnsafeMutablePointer<attrlist>.allocate(capacity: 1)
        defer { returnAttributes.deallocate() }
        returnAttributes.initialize(to: attrlist())
        returnAttributes.pointee.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        // APFS 的对象 ID 超过 32 位，必须取 64 位的 FILEID 才能用 fsgetpath 还原路径
        returnAttributes.pointee.commonattr = attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID)

        var searchBlock = fssearchblock()
        searchBlock.returnattrs = returnAttributes
        searchBlock.returnbuffer = buffer
        searchBlock.returnbuffersize = Self.bufferSize
        searchBlock.maxmatches = UInt(Self.maximumMatchesPerCall)
        searchBlock.timelimit = timeval(tv_sec: 0, tv_usec: Self.timeLimitMicroseconds)
        // 只按名称搜索时第二组参数不参与比较，但内核要求两组参数大小一致
        searchBlock.searchparams1 = parameters
        searchBlock.sizeofsearchparams1 = parameterSize
        searchBlock.searchparams2 = parameters
        searchBlock.sizeofsearchparams2 = parameterSize
        searchBlock.searchattrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        searchBlock.searchattrs.commonattr = attrgroup_t(ATTR_CMN_NAME)

        var state = searchstate()
        var options = UInt32(SRCHFS_START | SRCHFS_MATCHPARTIALNAMES | SRCHFS_MATCHFILES | SRCHFS_MATCHDIRS)
        var isFirstCall = true
        var restartCount = 0
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
        defer { pathBuffer.deallocate() }

        while true {
            var matchCount: UInt = 0
            let status = searchfs(volumePath, &searchBlock, &matchCount, Self.utf8ScriptCode, options, &state)
            let searchErrno = status == 0 ? 0 : errno
            options &= ~UInt32(SRCHFS_START)

            // 两次调用之间卷目录发生了变化（例如有程序在写入），内核要求从头开始；已回调的结果由调用方去重
            if status != 0, searchErrno == EBUSY, isFirstCall == false, restartCount < Self.maximumRestarts {
                restartCount += 1
                state = searchstate()
                options |= UInt32(SRCHFS_START)
                continue
            }
            if status != 0, searchErrno != EAGAIN {
                throw isFirstCall
                    ? VolumeCatalogSearchError.unsupported(errno: searchErrno)
                    : VolumeCatalogSearchError.interrupted(errno: searchErrno)
            }
            isFirstCall = false

            var matches: [VolumeCatalogMatch] = []
            matches.reserveCapacity(Int(matchCount))
            var entry = buffer
            for _ in 0..<matchCount {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                if let match = Self.parseMatch(entry + MemoryLayout<UInt32>.size, volumeID: &volumeID, pathBuffer: pathBuffer) {
                    matches.append(match)
                }
                entry += length
            }
            if matches.isEmpty == false {
                onMatches(matches)
            }

            // status == 0 表示整卷已搜索完毕
            if status == 0 || shouldStop() {
                return
            }
        }
    }

    /// 返回的属性按位序排列：name（attrreference_t）、objtype、fileid
    private static func parseMatch(
        _ start: UnsafeMutableRawPointer,
        volumeID: inout fsid_t,
        pathBuffer: UnsafeMutablePointer<CChar>
    ) -> VolumeCatalogMatch? {
        var field = start + MemoryLayout<attrreference_t>.size
        let objectType = field.loadUnaligned(as: fsobj_type_t.self)
        field += MemoryLayout<fsobj_type_t>.size
        let fileID = field.loadUnaligned(as: UInt64.self)

        // 条目在搜索期间被删除、或调用者无权访问其所在目录时取不到路径
        guard fsgetpath(pathBuffer, Int(MAXPATHLEN), &volumeID, fileID) > 0 else {
            return nil
        }
        return VolumeCatalogMatch(path: String(cString: pathBuffer), isDirectory: objectType == VDIR.rawValue)
    }
}
