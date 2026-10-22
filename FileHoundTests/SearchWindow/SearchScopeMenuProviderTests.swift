import Foundation
import Testing
@testable import FileHound

struct SearchScopeMenuProviderTests {
    /// 按 /Volumes/<name> 构造挂载卷，仅用于名字与挂载点一致的普通场景
    private static func volumes(_ names: [String]) -> [SearchScopeMountedVolume] {
        names.map { SearchScopeMountedVolume(name: $0, path: "/Volumes/\($0)") }
    }

    @Test
    func buildsPresetRecentAndMountedSections() {
        let provider = SearchScopeMenuProvider(
            mountedVolumes: { Self.volumes(["Macintosh HD", "CC Switch"]) },
            recentLocations: [
                RecentLocationRecord(
                    scope: SearchScopeSnapshot(
                        title: "inside Downloads",
                        representedPath: "/Users/test/Downloads",
                        scopeDescription: "Downloads",
                        sourceKind: .folder
                    )
                )
            ]
        )

        let sections = provider.sections()

        #expect(sections.count == 2)
        #expect(sections[0].items.map(\.title).contains(L10n.string("search_scope.startup_volume")))
        #expect(sections[1].title == L10n.string("search_scope.recent_locations"))
        #expect(sections[1].items.map(\.title) == [L10n.format("search_scope.inside_named_folder", "Downloads"), L10n.format("search_scope.on_volume", "CC Switch")])
        #expect(sections[1].items.first?.representedPath == "/Users/test/Downloads")
        #expect(sections[0].items.first?.keyEquivalent == "0")
        #expect(sections[1].items.last?.icon != nil)
    }

    @Test
    func filtersSystemAndSimulatorVolumesFromMountedSection() {
        let provider = SearchScopeMenuProvider(
            mountedVolumes: { Self.volumes(["Macintosh HD", "Preboot", "VM", "iOS 26.4 Simulator", "CC Switch"]) },
            recentLocations: []
        )

        let mountedTitles = provider.sections()[1].items.map(\.title)

        #expect(mountedTitles == [L10n.format("search_scope.on_volume", "CC Switch")])
    }

    @Test
    func deduplicatesMountedVolumesAlreadyPresentInRecentLocations() {
        let provider = SearchScopeMenuProvider(
            mountedVolumes: { Self.volumes(["Shared"]) },
            recentLocations: [
                RecentLocationRecord(
                    scope: SearchScopeSnapshot(
                        title: L10n.format("search_scope.on_volume", "Shared"),
                        representedPath: "/Volumes/Shared",
                        scopeDescription: "Shared",
                        sourceKind: .mountedVolume
                    )
                )
            ]
        )

        let recentSectionItems = provider.sections()[1].items

        #expect(recentSectionItems.count == 1)
        #expect(recentSectionItems.first?.representedPath == "/Volumes/Shared")
    }

    @Test
    func sameNamedVolumesUseTheirRealMountPaths() {
        let provider = SearchScopeMenuProvider(
            mountedVolumes: {
                [
                    SearchScopeMountedVolume(name: "Untitled", path: "/Volumes/Untitled"),
                    SearchScopeMountedVolume(name: "Untitled", path: "/Volumes/Untitled 1")
                ]
            },
            recentLocations: []
        )

        let items = provider.sections()[1].items

        #expect(items.map(\.representedPath) == ["/Volumes/Untitled", "/Volumes/Untitled 1"])
        #expect(items.map(\.scopeDescription) == ["Untitled", "Untitled"])
        // 同名卷宗标题附带挂载点目录名以便区分
        #expect(Set(items.map(\.title)).count == 2)
    }

    @Test
    func volumeMountedAtCustomPathKeepsThatPath() {
        let provider = SearchScopeMenuProvider(
            mountedVolumes: { [SearchScopeMountedVolume(name: "Backup", path: "/Volumes/Backup-1")] },
            recentLocations: []
        )

        let item = provider.sections()[1].items.first

        #expect(item?.representedPath == "/Volumes/Backup-1")
        #expect(item?.title == L10n.format("search_scope.on_volume", "Backup"))
    }

    @Test
    func mountedVolumesAreReadEachTimeSectionsAreBuilt() {
        var mounted = Self.volumes(["Disk A"])
        let provider = SearchScopeMenuProvider(mountedVolumes: { mounted }, recentLocations: [])
        #expect(provider.sections()[1].items.map(\.representedPath) == ["/Volumes/Disk A"])

        // 插入新磁盘后再次生成菜单即可看到
        mounted.append(contentsOf: Self.volumes(["Disk B"]))
        #expect(provider.sections()[1].items.map(\.representedPath) == ["/Volumes/Disk A", "/Volumes/Disk B"])

        mounted.removeAll()
        #expect(provider.sections()[1].items.isEmpty)
    }
}

struct SearchScopeDropResolverTests {
    @Test
    func folderIsUsedDirectly() throws {
        let tree = try TemporaryFixtureTree.make { try $0.file("Docs/report.txt", contents: "report") }
        defer { try? FileManager.default.removeItem(at: tree.rootURL) }
        let folderURL = tree.rootURL.appendingPathComponent("Docs", isDirectory: true)

        #expect(SearchScopeDropResolver.folderURL(from: [folderURL])?.path == folderURL.path)
    }

    @Test
    func fileUsesItsParentFolder() throws {
        let tree = try TemporaryFixtureTree.make { try $0.file("Docs/report.txt", contents: "report") }
        defer { try? FileManager.default.removeItem(at: tree.rootURL) }
        let fileURL = tree.rootURL.appendingPathComponent("Docs/report.txt")

        #expect(SearchScopeDropResolver.folderURL(from: [fileURL])?.path == tree.rootURL.appendingPathComponent("Docs").path)
    }

    @Test
    func multipleItemsUseFirstFileURL() throws {
        let webURL = try #require(URL(string: "https://example.com/folder"))
        let first = URL(fileURLWithPath: "/Users/test/First")
        let second = URL(fileURLWithPath: "/Users/test/Second")

        let resolved = SearchScopeDropResolver.folderURL(from: [webURL, first, second], isFolder: { _ in true })

        #expect(resolved?.path == "/Users/test/First")
    }

    @Test
    func packagesAndFilesResolveToContainingFolder() {
        let appURL = URL(fileURLWithPath: "/Applications/Utilities/Tool.app")

        let resolved = SearchScopeDropResolver.folderURL(from: [appURL], isFolder: { _ in false })

        #expect(resolved?.path == "/Applications/Utilities")
    }

    @Test
    func volumeRootIsUsedAsFolder() {
        let volumeURL = URL(fileURLWithPath: "/Volumes/Untitled 1")

        let resolved = SearchScopeDropResolver.folderURL(from: [volumeURL], isFolder: { _ in true })

        #expect(resolved?.path == "/Volumes/Untitled 1")
    }

    @Test
    func emptyOrNonFileURLsResolveToNil() throws {
        #expect(SearchScopeDropResolver.folderURL(from: []) == nil)
        #expect(SearchScopeDropResolver.folderURL(from: [try #require(URL(string: "https://example.com"))]) == nil)
    }
}
