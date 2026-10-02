import Darwin
import Foundation

struct LocalFilesystemProvider: FilesystemAccessProviding, Sendable {
    let kind: ProviderKind = .local

    init() {}

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }

    func listDirectory(atPath path: String) throws -> [DirectoryListingItem] {
        try BulkDirectoryLister.list(atPath: path)
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: path)
    }

    /// 不超过这个大小的文件一次读入内存；更大的文件改用内存映射，避免多个线程同时读大文件时占用过多内存
    private static let wholeReadLimit = 64 << 20

    /// 内容搜索要读遍大量文件，读取速度决定了整体耗时。按缺页逐页读入映射文件时每次 IO 只有几十 KB，
    /// 未缓存时吞吐只有直接 read 的三分之一左右，所以小文件直接读，大文件映射后提示内核顺序预读
    func contentsOfFile(atPath path: String) throws -> Data {
        // O_NONBLOCK：遇到命名管道时 open 不会阻塞，交给下面的通用读取处理
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0,
              info.st_size <= Self.wholeReadLimit else {
            return try Self.mappedContents(atPath: path)
        }

        let size = Int(info.st_size)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        var offset = 0
        while offset < size {
            let count = pread(descriptor, buffer + offset, size - offset, off_t(offset))
            if count < 0, errno == EINTR {
                continue
            }
            guard count > 0 else {
                break
            }
            offset += count
        }
        if offset == 0, size > 0 {
            buffer.deallocate()
            return try Self.mappedContents(atPath: path)
        }
        return Data(bytesNoCopy: buffer, count: offset, deallocator: .custom { pointer, _ in pointer.deallocate() })
    }

    private static func mappedContents(atPath path: String) throws -> Data {
        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress, bytes.count > 0 else {
                return
            }
            // 映射的起始地址按页对齐；未映射（如网络卷上）时 madvise 对普通内存也无副作用
            let pageMask = UInt(getpagesize() - 1)
            let start = UInt(bitPattern: base) & ~pageMask
            let length = bytes.count + Int(UInt(bitPattern: base) - start)
            guard let pointer = UnsafeMutableRawPointer(bitPattern: start) else {
                return
            }
            madvise(pointer, length, MADV_SEQUENTIAL)
            madvise(pointer, length, MADV_WILLNEED)
        }
        return data
    }
}

/// 用 getattrlistbulk 一次系统调用批量取回目录中多个子项的名称与类型，
/// 比 contentsOfDirectory + 逐项 attributesOfItem 快一个数量级
enum BulkDirectoryLister {
    private static let bufferSize = 128 * 1024

    static func list(atPath path: String) throws -> [DirectoryListingItem] {
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }

        var attributeList = attrlist()
        attributeList.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributeList.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_ERROR)
            | attrgroup_t(ATTR_CMN_OBJTYPE)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        var items: [DirectoryListingItem] = []
        var isFirstBatch = true
        while true {
            let count = getattrlistbulk(descriptor, &attributeList, buffer, bufferSize, 0)
            if count == 0 {
                break
            }
            if count < 0 {
                // 首批就失败说明目录不可读；中途失败则保留已读到的部分
                if isFirstBatch {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                break
            }
            isFirstBatch = false

            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                if let item = parseEntry(entry + MemoryLayout<UInt32>.size) {
                    items.append(item)
                }
                entry += length
            }
        }
        return items
    }

    /// 返回的属性按 ATTR_CMN_* 位序紧密排列：returned_attrs、error、name、objtype
    private static func parseEntry(_ start: UnsafeMutableRawPointer) -> DirectoryListingItem? {
        var field = start
        let returned = field.loadUnaligned(as: attribute_set_t.self)
        field += MemoryLayout<attribute_set_t>.size

        if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
            field += MemoryLayout<UInt32>.size
        }

        guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else {
            return nil
        }
        let nameReference = field.loadUnaligned(as: attrreference_t.self)
        let name = String(cString: (field + Int(nameReference.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
        field += MemoryLayout<attrreference_t>.size

        guard returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 else {
            return nil
        }
        let objectType = field.loadUnaligned(as: fsobj_type_t.self)
        return DirectoryListingItem(name: name, isDirectory: objectType == VDIR.rawValue)
    }
}
