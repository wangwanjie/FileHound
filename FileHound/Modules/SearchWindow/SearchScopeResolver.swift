import Foundation

/// 预设范围的稳定标识，与菜单项 / 已保存快照里的 scopeDescription 一致
enum SearchScopePreset: String, CaseIterable, Sendable {
    case startupVolume = "Macintosh HD"
    case allDisks = "All Disks"
    case localDisks = "Local Disks"
    case networkVolumes = "Network Volumes"
    case finderSelection = "Finder Selection"
}

struct SearchScopeVolume: Equatable, Sendable {
    let path: String
    let isLocal: Bool
}

struct ResolvedSearchScope: Equatable, Sendable {
    let rootPaths: [String]
    let excludedPaths: [String]
}

struct SearchScopeResolver {
    /// 从 "/" 遍历时需要跳过的系统路径：其他卷宗挂载点、Data 卷的固件链接副本、设备文件与自动挂载点
    static let startupVolumeExclusions = [
        "/Volumes",
        "/System/Volumes",
        "/dev",
        "/private/var/vm",
        "/.vol",
        "/Network",
        "/net"
    ]

    var mountedVolumes: () -> [SearchScopeVolume]
    var finderSelection: () -> [String]?

    init(
        mountedVolumes: @escaping () -> [SearchScopeVolume] = SearchScopeResolver.currentMountedVolumes,
        finderSelection: @escaping () -> [String]? = FinderSelectionReader.selectedFolderPaths
    ) {
        self.mountedVolumes = mountedVolumes
        self.finderSelection = finderSelection
    }

    func resolve(_ scope: SearchScopeSnapshot) -> ResolvedSearchScope {
        guard scope.sourceKind == .preset, let preset = SearchScopePreset(rawValue: scope.scopeDescription) else {
            return ResolvedSearchScope(rootPaths: [scope.rootPath], excludedPaths: [])
        }

        switch preset {
        case .startupVolume:
            return ResolvedSearchScope(rootPaths: ["/"], excludedPaths: Self.startupVolumeExclusions)
        case .allDisks:
            return ResolvedSearchScope(
                rootPaths: ["/"] + mountedVolumes().map(\.path),
                excludedPaths: Self.startupVolumeExclusions
            )
        case .localDisks:
            return ResolvedSearchScope(
                rootPaths: ["/"] + mountedVolumes().filter(\.isLocal).map(\.path),
                excludedPaths: Self.startupVolumeExclusions
            )
        case .networkVolumes:
            return ResolvedSearchScope(
                rootPaths: mountedVolumes().filter { $0.isLocal == false }.map(\.path),
                excludedPaths: []
            )
        case .finderSelection:
            let paths = finderSelection() ?? []
            return ResolvedSearchScope(
                rootPaths: paths.isEmpty ? [NSHomeDirectory()] : paths,
                excludedPaths: []
            )
        }
    }

    /// 除启动卷外的可浏览卷宗（外置盘、磁盘映像、网络共享）
    static func currentMountedVolumes() -> [SearchScopeVolume] {
        let keys: [URLResourceKey] = [.volumeIsBrowsableKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [])
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.volumeIsBrowsable == true,
                      values.volumeIsRootFileSystem != true,
                      url.path != "/",
                      url.path.hasPrefix("/System/Volumes") == false else {
                    return nil
                }
                return SearchScopeVolume(path: url.path, isLocal: values.volumeIsLocal ?? true)
            }
    }
}

enum FinderSelectionReader {
    /// Finder 中选中的文件夹；没有选中文件夹时返回最前窗口的目标文件夹（无窗口时为桌面）
    static func selectedFolderPaths() -> [String]? {
        let source = """
        tell application "Finder"
            set output to ""
            repeat with selectedItem in (get selection)
                try
                    set output to output & POSIX path of (selectedItem as alias) & linefeed
                end try
            end repeat
            try
                set output to output & "@insertion:" & POSIX path of (insertion location as alias)
            end try
            return output
        end tell
        """
        guard let script = NSAppleScript(source: source) else {
            return nil
        }

        var error: NSDictionary?
        guard let output = script.executeAndReturnError(&error).stringValue, error == nil else {
            return nil
        }
        return folderPaths(fromScriptOutput: output)
    }

    static func folderPaths(
        fromScriptOutput output: String,
        isDirectory: (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    ) -> [String] {
        var selectedFolders: [String] = []
        var insertionLocation: String?

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("@insertion:") {
                insertionLocation = String(line.dropFirst("@insertion:".count))
            } else if isDirectory(line) {
                selectedFolders.append(normalized(line))
            }
        }

        if selectedFolders.isEmpty, let insertionLocation, insertionLocation.isEmpty == false {
            return [normalized(insertionLocation)]
        }
        return selectedFolders
    }

    private static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
