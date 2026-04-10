import Testing
@testable import FileHound

struct SearchScopeMenuProviderTests {
    @Test
    func buildsPresetRecentAndMountedSections() {
        let provider = SearchScopeMenuProvider(
            mountedVolumes: ["Macintosh HD", "CC Switch"],
            recentLocations: ["Downloads"]
        )

        let sections = provider.sections()

        #expect(sections.count == 3)
        #expect(sections[0].items.map(\.title).contains("on startup volume"))
        #expect(sections[1].title == "Recent Locations")
        #expect(sections[2].items.map(\.title) == ["on CC Switch"])
    }

    @Test
    func filtersSystemAndSimulatorVolumesFromMountedSection() {
        let provider = SearchScopeMenuProvider(
            mountedVolumes: ["Macintosh HD", "Preboot", "VM", "iOS 26.4 Simulator", "CC Switch"],
            recentLocations: []
        )

        let mountedTitles = provider.sections()[2].items.map(\.title)

        #expect(mountedTitles == ["on CC Switch"])
    }
}
