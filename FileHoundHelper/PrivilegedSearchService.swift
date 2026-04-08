import Foundation

final class PrivilegedSearchService: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private let listener = NSXPCListener(machServiceName: "cn.vanjay.FileHound.Helper")

    func run() {
        listener.delegate = self
        listener.resume()
        RunLoop.main.run()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
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
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            reply(Data(data.prefix(maxBytes)), nil)
        } catch {
            reply(nil, error as NSError)
        }
    }
}
