import AppKit

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
    let sourceKind: SearchScopeSourceKind
    let shortcutIndex: Int?

    init(
        title: String,
        representedPath: String?,
        scopeDescription: String,
        kind: SearchScopeMenuItemKind = .standard,
        sourceKind: SearchScopeSourceKind = .preset,
        shortcutIndex: Int? = nil
    ) {
        self.title = title
        self.representedPath = representedPath
        self.scopeDescription = scopeDescription
        self.kind = kind
        self.sourceKind = sourceKind
        self.shortcutIndex = shortcutIndex
    }

    var identifier: String {
        [
            sourceKind.rawValue,
            kind == .folderPicker ? "folderPicker" : "standard",
            representedPath ?? "",
            scopeDescription,
            title
        ].joined(separator: "|")
    }

    var snapshot: SearchScopeSnapshot {
        SearchScopeSnapshot(
            title: title,
            representedPath: representedPath,
            scopeDescription: scopeDescription,
            sourceKind: sourceKind
        )
    }

    var keyEquivalent: String {
        guard let shortcutIndex, (0...9).contains(shortcutIndex) else {
            return ""
        }
        return String(shortcutIndex)
    }

    var icon: NSImage? {
        switch sourceKind {
        case .preset:
            return presetIcon
        case .mountedVolume:
            return representedPath.flatMap(NSWorkspace.shared.icon(forFile:))
        case .folder, .recentLocation:
            guard let representedPath else {
                return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            }
            return NSWorkspace.shared.icon(forFile: representedPath)
        }
    }

    private var presetIcon: NSImage? {
        switch SearchScopePreset(rawValue: scopeDescription) {
        case .startupVolume:
            return NSWorkspace.shared.icon(forFile: "/")
        case .allDisks:
            return NSImage(systemSymbolName: "internaldrive.2", accessibilityDescription: nil)
        case .localDisks:
            return NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil)
        case .networkVolumes:
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        case .finderSelection:
            return NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        case nil:
            return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        }
    }
}

struct SearchScopeMenuProvider {
    var mountedVolumes: [String]
    var recentLocations: [RecentLocationRecord]

    init(
        mountedVolumes: [String] = Self.defaultMountedVolumes(),
        recentLocations: [RecentLocationRecord] = Self.defaultRecentLocations()
    ) {
        self.mountedVolumes = mountedVolumes
        self.recentLocations = recentLocations
    }

    func sections() -> [SearchScopeMenuSection] {
        let presetItems = [
            SearchScopeMenuItem(
                title: L10n.string("search_scope.startup_volume"),
                representedPath: "/",
                scopeDescription: SearchScopePreset.startupVolume.rawValue,
                sourceKind: .preset
            ),
            SearchScopeMenuItem(
                title: L10n.string("search_scope.all_disks"),
                representedPath: "/",
                scopeDescription: SearchScopePreset.allDisks.rawValue,
                sourceKind: .preset
            ),
            SearchScopeMenuItem(
                title: L10n.string("search_scope.local_disks"),
                representedPath: "/",
                scopeDescription: SearchScopePreset.localDisks.rawValue,
                sourceKind: .preset
            ),
            SearchScopeMenuItem(
                title: L10n.string("search_scope.network_volumes"),
                representedPath: "/Volumes",
                scopeDescription: SearchScopePreset.networkVolumes.rawValue,
                sourceKind: .preset
            ),
            SearchScopeMenuItem(
                title: L10n.string("search_scope.finder_selection"),
                representedPath: nil,
                scopeDescription: SearchScopePreset.finderSelection.rawValue,
                sourceKind: .preset
            ),
            SearchScopeMenuItem(
                title: L10n.string("search_scope.inside_folder"),
                representedPath: nil,
                scopeDescription: "Chosen Folder",
                kind: .folderPicker,
                sourceKind: .folder
            )
        ]

        let recentItems = deduplicatedItems(recentLocations.map { record in
            SearchScopeMenuItem(
                title: localizedTitle(for: record.scope),
                representedPath: record.scope.representedPath,
                scopeDescription: record.scope.scopeDescription,
                sourceKind: record.scope.sourceKind == .mountedVolume ? .mountedVolume : .recentLocation
            )
        })

        let recentPaths = Set(recentItems.compactMap(\.representedPath))
        let mountedItems = deduplicatedItems(
            mountedVolumes
                .filter(Self.isVisibleMountedVolumeName)
                .map { volumeName in
                    SearchScopeMenuItem(
                        title: L10n.format("search_scope.on_volume", volumeName),
                        representedPath: "/Volumes/\(volumeName)",
                        scopeDescription: volumeName,
                        sourceKind: .mountedVolume
                    )
                }
            .filter { item in
                guard let representedPath = item.representedPath else {
                    return true
                }
                return recentPaths.contains(representedPath) == false
            }
        )

        let sections = [
            SearchScopeMenuSection(title: nil, items: presetItems),
            SearchScopeMenuSection(
                title: recentItems.isEmpty && mountedItems.isEmpty ? nil : L10n.string("search_scope.recent_locations"),
                items: recentItems + mountedItems
            )
        ]

        return assignShortcutIndices(to: sections)
    }

    private func deduplicatedItems(_ items: [SearchScopeMenuItem]) -> [SearchScopeMenuItem] {
        var seenKeys = Set<String>()
        var deduplicatedItems: [SearchScopeMenuItem] = []

        for item in items {
            let dedupeKey = item.representedPath ?? item.identifier
            guard seenKeys.insert(dedupeKey).inserted else {
                continue
            }
            deduplicatedItems.append(item)
        }

        return deduplicatedItems
    }

    private func localizedTitle(for scope: SearchScopeSnapshot) -> String {
        switch scope.sourceKind {
        case .folder, .recentLocation:
            let folderName = scope.representedPath
                .flatMap { URL(fileURLWithPath: $0).lastPathComponent.nilIfEmpty }
                ?? scope.scopeDescription
            return L10n.format("search_scope.inside_named_folder", folderName)
        case .mountedVolume:
            return L10n.format("search_scope.on_volume", scope.scopeDescription)
        case .preset:
            return scope.title
        }
    }

    private func assignShortcutIndices(to sections: [SearchScopeMenuSection]) -> [SearchScopeMenuSection] {
        var nextShortcutIndex = 0

        return sections.map { section in
            let items = section.items.map { item -> SearchScopeMenuItem in
                let assignedShortcut = nextShortcutIndex <= 9 ? nextShortcutIndex : nil
                if assignedShortcut != nil {
                    nextShortcutIndex += 1
                }
                return SearchScopeMenuItem(
                    title: item.title,
                    representedPath: item.representedPath,
                    scopeDescription: item.scopeDescription,
                    kind: item.kind,
                    sourceKind: item.sourceKind,
                    shortcutIndex: assignedShortcut
                )
            }
            return SearchScopeMenuSection(title: section.title, items: items)
        }
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

    private static func defaultRecentLocations() -> [RecentLocationRecord] {
        RecentLocationStore.shared.all()
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension NSImage {
    func scopeMenuScaled() -> NSImage {
        let scaledImage = copy() as? NSImage ?? self
        scaledImage.size = NSSize(width: 16, height: 16)
        return scaledImage
    }
}
