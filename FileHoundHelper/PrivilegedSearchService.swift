import Foundation

final class PrivilegedSearchService: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private let listener = NSXPCListener(machServiceName: "cn.vanjay.FileHound.Helper")

    func run() {
        listener.delegate = self
        listener.resume()
        RunLoop.main.run()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // TODO: 安装为特权 Helper（以 root 运行）之前，必须在这里校验调用方的代码签名，只接受本 App
        // （cn.vanjay.FileHound，且为同一 Team ID 签名）的连接；否则任意本地进程都能借助本服务以 root 权限
        // 枚举目录、读取任意文件。macOS 13+ 可用 setCodeSigningRequirement(_:)；macOS 12 需取连接的 audit token
        // （NSXPCConnection 未公开该属性），再用 SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)
        // + SecCodeCheckValidity 按 designated requirement 校验。不要改用 processIdentifier 校验：PID 可被复用，存在竞态。
        // 当前 Helper 只是骨架、未被安装，暂未实现校验
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func enumerate(path: String, reply: @escaping ([String], NSError?) -> Void) {
        do {
            let items = try FileManager.default.contentsOfDirectory(atPath: path)
            reply(items, nil)
        } catch {
            reply([], error as NSError)
        }
    }

    func read(path: String, maxBytes: Int, reply: @escaping (Data?, NSError?) -> Void) {
        // 只读取前 maxBytes 字节，避免为了取文件开头把整个（可能很大的）文件读进内存
        guard maxBytes > 0 else {
            reply(Data(), nil)
            return
        }

        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer {
                try? handle.close()
            }
            let data = try handle.read(upToCount: maxBytes) ?? Data()
            reply(data, nil)
        } catch {
            reply(nil, error as NSError)
        }
    }
}
