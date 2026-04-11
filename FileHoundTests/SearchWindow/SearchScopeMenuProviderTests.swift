import Testing
@testable import FileHound

struct SearchScopeMenuProviderTests {
    @Test
    func buildsPresetRecentAndMountedSections() {
        let provider = SearchScopeMenuProvider(
            mountedVolumes: ["Macintosh HD", "CC Switch"],
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
            mountedVolumes: ["Macintosh HD", "Preboot", "VM", "iOS 26.4 Simulator", "CC Switch"],
            recentLocations: []
        )

        let mountedTitles = provider.sections()[1].items.map(\.title)

        #expect(mountedTitles == [L10n.format("search_scope.on_volume", "CC Switch")])
    }

    @Test
    func deduplicatesMountedVolumesAlreadyPresentInRecentLocations() {
        let provider = SearchScopeMenuProvider(
            mountedVolumes: ["Shared"],
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
}
