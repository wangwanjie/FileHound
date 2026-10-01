import CoreServices
import Foundation

/// 读取 Finder「简介」里的注释：优先读扩展属性，缺失时回退到 Spotlight 元数据
enum FinderCommentReader {
    static let extendedAttributeName = "com.apple.metadata:kMDItemFinderComment"

    static func comment(atPath path: String) -> String? {
        if let comment = extendedAttributeComment(atPath: path) {
            return comment
        }
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else {
            return nil
        }
        return MDItemCopyAttribute(item, kMDItemFinderComment) as? String
    }

    static func extendedAttributeComment(atPath path: String) -> String? {
        let length = getxattr(path, extendedAttributeName, nil, 0, 0, XATTR_NOFOLLOW)
        guard length > 0 else {
            return nil
        }
        var data = Data(count: length)
        let readLength = data.withUnsafeMutableBytes { buffer in
            getxattr(path, extendedAttributeName, buffer.baseAddress, length, 0, XATTR_NOFOLLOW)
        }
        guard readLength == length else {
            return nil
        }
        if let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? String {
            return value
        }
        return String(data: data, encoding: .utf8)
    }
}

/// 提取脚本文件的源码：已编译的 AppleScript 经 osadecompile 反编译，文本脚本按扩展名或 shebang 识别
struct ScriptSourceReader {
    static let compiledScriptExtensions: Set<String> = ["scpt", "scptd"]
    static let textScriptExtensions: Set<String> = [
        "applescript", "sh", "bash", "zsh", "fish", "command", "tool",
        "py", "rb", "pl", "pm", "php", "js", "mjs", "ts", "lua", "tcl", "swift", "jxa"
    ]
    static let maximumTextScriptSize = 1_048_576

    var decompile: (String) -> String? = ScriptSourceReader.decompileWithOSA

    func source(
        atPath path: String,
        isDirectory: Bool,
        fileSize: Int64?,
        readContents: (String) throws -> Data
    ) -> String? {
        let pathExtension = (path as NSString).pathExtension.lowercased()
        if Self.compiledScriptExtensions.contains(pathExtension) {
            return decompile(path)
        }
        guard isDirectory == false, (fileSize ?? 0) <= Int64(Self.maximumTextScriptSize),
              let data = try? readContents(path),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        if Self.textScriptExtensions.contains(pathExtension) || text.hasPrefix("#!") {
            return text
        }
        return nil
    }

    static func decompileWithOSA(_ path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osadecompile")
        process.arguments = [path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
