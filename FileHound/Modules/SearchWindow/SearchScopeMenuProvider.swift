import Foundation

enum SearchScopeMenuItemKind: Equatable, Sendable {
    case standard
    case folderPicker
}

struct SearchScopeMenuSection: Equatable, Sendable {
    let title: String?
    let items: [SearchScopeMenuItem]
}

struct SearchScopeMenuItem: Equatable, Sendable {
    let title: String
    let representedPath: String?
    let scopeDescription: String
    let kind: SearchScopeMenuItemKind

    init(
        title: String,
        representedPath: String?,
        scopeDescription: String,
        kind: SearchScopeMenuItemKind = .standard
    ) {
        self.title = title
        self.representedPath = representedPath
        self.scopeDescription = scopeDescription
        self.kind = kind
    }
}

struct SearchScopeMenuProvider {
    var mountedVolumes: [String]
    var recentLocations: [String]

    init(
        mountedVolumes: [String] = Self.defaultMountedVolumes(),
        recentLocations: [String] = []
    ) {
        self.mountedVolumes = mountedVolumes
        self.recentLocations = recentLocations
    }

    func sections() -> [SearchScopeMenuSection] {
        let presets = SearchScopeMenuSection(
            title: nil,
            items: [
                .init(title: "on startup volume", representedPath: "/", scopeDescription: "Macintosh HD"),
                .init(title: "on all disks", representedPath: "/", scopeDescription: "All Disks"),
                .init(title: "on local disks", representedPath: "/", scopeDescription: "Local Disks"),
                .init(title: "on network volumes", representedPath: "/Volumes", scopeDescription: "Network Volumes"),
                .init(title: "in Finder selection", representedPath: NSHomeDirectory(), scopeDescription: "Finder Selection"),
                .init(
                    title: "inside folder...",
                    representedPath: nil,
                    scopeDescription: "Chosen Folder",
                    kind: .folderPicker
                )
            ]
        )

        let recent = SearchScopeMenuSection(
            title: "Recent Locations",
            items: recentLocations.map {
                .init(title: $0, representedPath: nil, scopeDescription: $0)
            }
        )

        let mounted = SearchScopeMenuSection(
            title: nil,
            items: mountedVolumes
                .filter(Self.isVisibleMountedVolumeName)
                .map {
                .init(title: "on \($0)", representedPath: "/Volumes/\($0)", scopeDescription: $0)
            }
        )

        return [presets, recent, mounted]
    }

    private static func defaultMountedVolumes() -> [String] {
        let keys: Set<URLResourceKey> = [.volumeIsBrowsableKey, .volumeNameKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: []) ?? [])
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.volumeIsBrowsable == true,
                      url.path != "/" else {
                    return nil
                }

                return values.volumeName ?? url.lastPathComponent
            }
            .filter(isVisibleMountedVolumeName)
    }

    static func isVisibleMountedVolumeName(_ name: String) -> Bool {
        guard name.isEmpty == false else {
            return false
        }

        let excludedNames: Set<String> = [
            "Macintosh HD",
            "Preboot",
            "VM",
            "Update",
            "xART",
            "iSCPreboot",
            "Hardware"
        ]

        if excludedNames.contains(name) {
            return false
        }

        if name.hasPrefix(".") {
            return false
        }

        return name.localizedCaseInsensitiveContains("simulator") == false
    }
}
