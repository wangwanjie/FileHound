import Foundation

@objc protocol HelperProtocol {
    func ping(reply: @escaping (Bool) -> Void)
    func enumerate(path: String, reply: @escaping ([String], NSError?) -> Void)
    func read(path: String, maxBytes: Int, reply: @escaping (Data?, NSError?) -> Void)
}
