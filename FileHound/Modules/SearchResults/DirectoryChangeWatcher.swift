import Foundation

/// 监听一组目录的内容变化（文件新增、移入、移出等），在主线程回调
final class DirectoryChangeWatcher {
    var onChange: (() -> Void)?

    private var sources: [String: DispatchSourceFileSystemObject] = [:]

    deinit {
        sources.values.forEach { $0.cancel() }
    }

    /// 更新监听的目录集合：新增的开始监听，不再需要的停止监听
    func watch(directories: Set<String>) {
        for (path, source) in sources where directories.contains(path) == false {
            source.cancel()
            sources[path] = nil
        }

        for path in directories where sources[path] == nil {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else {
                continue
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .link],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.onChange?()
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            sources[path] = source
        }
    }
}
