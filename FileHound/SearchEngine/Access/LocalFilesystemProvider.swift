import Darwin
import Foundation

struct LocalFilesystemProvider: FilesystemAccessProviding, Sendable {
    let kind: ProviderKind = .local

    init() {}

    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
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
