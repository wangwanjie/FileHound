import Foundation

struct SearchScopeMenuSection: Equatable, Sendable {
    let title: String?
    let items: [SearchScopeMenuItem]
}

struct SearchScopeMenuItem: Equatable, Sendable {
    let title: String
    let representedPath: String?
    let scopeDescription: String
}

struct SearchScopeMenuProvider {
    var mountedVolumes: [String]
    var recentLocations: [String]

    init(
        mountedVolumes: [String] = FileManager.default
            .mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])?
            .map(\.lastPathComponent) ?? [],
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
                .init(title: "inside folder...", representedPath: NSHomeDirectory(), scopeDescription: "Chosen Folder")
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
            items: mountedVolumes.map {
                .init(title: "on \($0)", representedPath: "/Volumes/\($0)", scopeDescription: $0)
            }
        )

        return [presets, recent, mounted]
    }
}
