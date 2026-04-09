import Testing
@testable import FileHound

struct AppSettingsTests {
    @Test
    func persistsUpdatePolicyAndFontSize() {
        let store = InMemoryKeyValueStore()
        let settings = AppSettings(storage: store)

        settings.updateCheckPolicy = .dailyAutomatic
        settings.resultsFontSize = 13

        #expect(settings.updateCheckPolicy == .dailyAutomatic)
        #expect(settings.resultsFontSize == 13)
    }
}
