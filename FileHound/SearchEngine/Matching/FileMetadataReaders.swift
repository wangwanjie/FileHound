import Foundation

/// 读取 Finder「简介」里的注释。访达把注释写在扩展属性 com.apple.metadata:kMDItemFinderComment 中，
/// 该属性不存在就视为没有注释；不再回退到 MDItemCreate：它每次都要经 XPC 询问 Spotlight，逐个文件调用时整盘搜索极慢
enum FinderCommentReader {
    static let extendedAttributeName = "com.apple.metadata:kMDItemFinderComment"

    static func comment(atPath path: String) -> String? {
        extendedAttributeComment(atPath: path)
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
struct ScriptSourceReader: Sendable {
    static let compiledScriptExtensions: Set<String> = ["scpt", "scptd"]
    static let textScriptExtensions: Set<String> = [
        "applescript", "sh", "bash", "zsh", "fish", "command", "tool",
        "py", "rb", "pl", "pm", "php", "js", "mjs", "ts", "lua", "tcl", "swift", "jxa"
    ]
    static let maximumTextScriptSize = 1_048_576

    var decompile: @Sendable (String) -> String? = { ScriptSourceReader.decompileWithOSA($0) }

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
