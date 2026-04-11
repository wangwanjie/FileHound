import Foundation
import MMKV

enum UpdateCheckPolicy: String, Codable, Sendable {
    case onLaunch
    case manualOnly
    case dailyAutomatic
}

protocol KeyValueStoring {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func data(forKey key: String) -> Data?
    func set(_ value: Data, forKey key: String)
}

extension KeyValueStoring {
    func codableValue<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = data(forKey: key) else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func setCodable<T: Encodable>(_ value: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        set(data, forKey: key)
    }
}

final class InMemoryKeyValueStore: KeyValueStoring {
    private var strings: [String: String] = [:]
    private var values: [String: Data] = [:]

    func string(forKey key: String) -> String? {
        strings[key]
    }

    func set(_ value: String, forKey key: String) {
        strings[key] = value
    }

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ value: Data, forKey key: String) {
        values[key] = value
    }
}

final class MMKVKeyValueStore: KeyValueStoring {
    static let shared = MMKVKeyValueStore()

    private let mmkv: MMKV

    static func initializeStore() {
        let rootURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FileHound/MMKV", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        MMKV.initialize(rootDir: rootURL.path)
    }

    private init() {
        if MMKV.default() == nil {
            Self.initializeStore()
        }
        guard let mmkv = MMKV.default() else {
            fatalError("MMKV 初始化失败")
        }
        self.mmkv = mmkv
    }

    func string(forKey key: String) -> String? {
        mmkv.string(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        mmkv.set(value, forKey: key)
    }

    func data(forKey key: String) -> Data? {
        mmkv.data(forKey: key)
    }

    func set(_ value: Data, forKey key: String) {
        mmkv.set(value, forKey: key)
    }
}

final class AppSettings {
    private enum Keys {
        static let preferredTheme = "preferredTheme"
        static let preferredLanguage = "preferredLanguage"
        static let updateCheckPolicy = "updateCheckPolicy"
        static let resultsFontSize = "resultsFontSize"
        static let dimColorHex = "dimColorHex"
        static let autoDownloadUpdates = "autoDownloadUpdates"
        static let launchShortcut = "launchShortcut"
        static let activationMode = "activationMode"
        static let openRecentSearchMenu = "openRecentSearchMenu"
        static let restorePreviousSearch = "restorePreviousSearch"
        static let tieResultsWindowToFindWindow = "tieResultsWindowToFindWindow"
        static let expandFoldersWhenShowingResults = "expandFoldersWhenShowingResults"
        static let showResultsEarly = "showResultsEarly"
        static let includeSpotlightResults = "includeSpotlightResults"
        static let quitWhenAllWindowsAreClosed = "quitWhenAllWindowsAreClosed"
        static let generalPreferences = "generalPreferences.v1"
        static let searchExecutionPreferences = "searchExecutionPreferences.v1"
        static let appearancePreferences = "appearancePreferences.v1"
        static let updatePreferences = "updatePreferences.v1"
    }

    static let shared = AppSettings(storage: MMKVKeyValueStore.shared)

    private let storage: KeyValueStoring

    init(storage: KeyValueStoring = MMKVKeyValueStore.shared) {
        self.storage = storage
    }

    var preferredTheme: AppTheme {
        get { rawPreferredTheme }
        set {
            storage.set(newValue.rawValue, forKey: Keys.preferredTheme)
            synchronizeAppearancePreferences()
        }
    }

    var preferredLanguage: AppLanguage {
        get { rawPreferredLanguage }
        set {
            storage.set(newValue.rawValue, forKey: Keys.preferredLanguage)
            synchronizeAppearancePreferences()
        }
    }

    var updateCheckPolicy: UpdateCheckPolicy {
        get { rawUpdateCheckPolicy }
        set {
            storage.set(newValue.rawValue, forKey: Keys.updateCheckPolicy)
            synchronizeUpdatePreferences()
        }
    }

    var resultsFontSize: Int {
        get { rawResultsFontSize }
        set {
            storage.set(String(newValue), forKey: Keys.resultsFontSize)
            synchronizeAppearancePreferences()
        }
    }

    var dimColorHex: String {
        get { rawDimColorHex }
        set {
            storage.set(newValue, forKey: Keys.dimColorHex)
            synchronizeAppearancePreferences()
        }
    }

    var autoDownloadUpdates: Bool {
        get { rawAutoDownloadUpdates }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.autoDownloadUpdates)
            synchronizeUpdatePreferences()
        }
    }

    var launchShortcut: String {
        get { storage.string(forKey: Keys.launchShortcut) ?? "" }
        set {
            storage.set(newValue, forKey: Keys.launchShortcut)
            synchronizeGeneralPreferences()
        }
    }

    var activationMode: SearchActivationMode {
        get {
            SearchActivationMode(rawValue: storage.string(forKey: Keys.activationMode) ?? SearchActivationMode.global.rawValue) ?? .global
        }
        set {
            storage.set(newValue.rawValue, forKey: Keys.activationMode)
            synchronizeGeneralPreferences()
        }
    }

    var openRecentSearchMenu: Bool {
        get { rawOpenRecentSearchMenu }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.openRecentSearchMenu)
            synchronizeGeneralPreferences()
        }
    }

    var restorePreviousSearch: Bool {
        get { rawRestorePreviousSearch }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.restorePreviousSearch)
            synchronizeGeneralPreferences()
        }
    }

    var tieResultsWindowToFindWindow: Bool {
        get { rawTieResultsWindowToFindWindow }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.tieResultsWindowToFindWindow)
            synchronizeGeneralPreferences()
        }
    }

    var expandFoldersWhenShowingResults: Bool {
        get { rawExpandFoldersWhenShowingResults }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.expandFoldersWhenShowingResults)
            synchronizeSearchExecutionPreferences()
        }
    }

    var showResultsEarly: Bool {
        get { rawShowResultsEarly }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.showResultsEarly)
            synchronizeSearchExecutionPreferences()
        }
    }

    var includeSpotlightResults: Bool {
        get { rawIncludeSpotlightResults }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.includeSpotlightResults)
            synchronizeSearchExecutionPreferences()
        }
    }

    var quitWhenAllWindowsAreClosed: Bool {
        get { rawQuitWhenAllWindowsAreClosed }
        set {
            storage.set(newValue ? "true" : "false", forKey: Keys.quitWhenAllWindowsAreClosed)
            synchronizeGeneralPreferences()
        }
    }

    var generalPreferences: GeneralSearchPreferences {
        get {
            (try? storage.codableValue(GeneralSearchPreferences.self, forKey: Keys.generalPreferences))
                ?? GeneralSearchPreferences(
                    launchShortcut: launchShortcut,
                    activationMode: activationMode,
                    openRecentSearchMenu: openRecentSearchMenu,
                    restorePreviousSearch: restorePreviousSearch,
                    tieResultsWindowToFindWindow: tieResultsWindowToFindWindow,
                    quitWhenAllWindowsAreClosed: quitWhenAllWindowsAreClosed
                )
        }
        set {
            storage.set(newValue.launchShortcut, forKey: Keys.launchShortcut)
            storage.set(newValue.activationMode.rawValue, forKey: Keys.activationMode)
            storage.set(newValue.openRecentSearchMenu ? "true" : "false", forKey: Keys.openRecentSearchMenu)
            storage.set(newValue.restorePreviousSearch ? "true" : "false", forKey: Keys.restorePreviousSearch)
            storage.set(newValue.tieResultsWindowToFindWindow ? "true" : "false", forKey: Keys.tieResultsWindowToFindWindow)
            storage.set(newValue.quitWhenAllWindowsAreClosed ? "true" : "false", forKey: Keys.quitWhenAllWindowsAreClosed)
            try? storage.setCodable(newValue, forKey: Keys.generalPreferences)
        }
    }

    var searchExecutionPreferences: SearchExecutionPreferences {
        get {
            (try? storage.codableValue(SearchExecutionPreferences.self, forKey: Keys.searchExecutionPreferences))
                ?? SearchExecutionPreferences(
                    expandFoldersWhenShowingResults: expandFoldersWhenShowingResults,
                    showResultsEarly: showResultsEarly,
                    includeSpotlightResults: includeSpotlightResults
                )
        }
        set {
            storage.set(newValue.expandFoldersWhenShowingResults ? "true" : "false", forKey: Keys.expandFoldersWhenShowingResults)
            storage.set(newValue.showResultsEarly ? "true" : "false", forKey: Keys.showResultsEarly)
            storage.set(newValue.includeSpotlightResults ? "true" : "false", forKey: Keys.includeSpotlightResults)
            try? storage.setCodable(newValue, forKey: Keys.searchExecutionPreferences)
        }
    }

    var appearancePreferences: AppearancePreferences {
        get {
            (try? storage.codableValue(AppearancePreferences.self, forKey: Keys.appearancePreferences))
                ?? AppearancePreferences(
                    preferredTheme: preferredTheme,
                    preferredLanguage: preferredLanguage,
                    resultsFontSize: resultsFontSize,
                    dimColorHex: dimColorHex
                )
        }
        set {
            storage.set(newValue.preferredTheme.rawValue, forKey: Keys.preferredTheme)
            storage.set(newValue.preferredLanguage.rawValue, forKey: Keys.preferredLanguage)
            storage.set(String(newValue.resultsFontSize), forKey: Keys.resultsFontSize)
            storage.set(newValue.dimColorHex, forKey: Keys.dimColorHex)
            try? storage.setCodable(newValue, forKey: Keys.appearancePreferences)
        }
    }

    var updatesPreferences: UpdatePreferences {
        get {
            (try? storage.codableValue(UpdatePreferences.self, forKey: Keys.updatePreferences))
                ?? UpdatePreferences(
                    updateCheckPolicy: updateCheckPolicy,
                    autoDownloadUpdates: autoDownloadUpdates
                )
        }
        set {
            storage.set(newValue.updateCheckPolicy.rawValue, forKey: Keys.updateCheckPolicy)
            storage.set(newValue.autoDownloadUpdates ? "true" : "false", forKey: Keys.autoDownloadUpdates)
            try? storage.setCodable(newValue, forKey: Keys.updatePreferences)
        }
    }

    private var rawPreferredTheme: AppTheme {
        AppTheme(rawValue: storage.string(forKey: Keys.preferredTheme) ?? AppTheme.system.rawValue) ?? .system
    }

    private var rawPreferredLanguage: AppLanguage {
        AppLanguage(rawValue: storage.string(forKey: Keys.preferredLanguage) ?? AppLanguage.system.rawValue) ?? .system
    }

    private var rawUpdateCheckPolicy: UpdateCheckPolicy {
        UpdateCheckPolicy(rawValue: storage.string(forKey: Keys.updateCheckPolicy) ?? UpdateCheckPolicy.onLaunch.rawValue) ?? .onLaunch
    }

    private var rawResultsFontSize: Int {
        Int(storage.string(forKey: Keys.resultsFontSize) ?? "13") ?? 13
    }

    private var rawDimColorHex: String {
        storage.string(forKey: Keys.dimColorHex) ?? "#A0A7B3"
    }

    private var rawAutoDownloadUpdates: Bool {
        storage.string(forKey: Keys.autoDownloadUpdates) == "true"
    }

    private var rawOpenRecentSearchMenu: Bool {
        storage.string(forKey: Keys.openRecentSearchMenu) != "false"
    }

    private var rawRestorePreviousSearch: Bool {
        storage.string(forKey: Keys.restorePreviousSearch) == "true"
    }

    private var rawTieResultsWindowToFindWindow: Bool {
        storage.string(forKey: Keys.tieResultsWindowToFindWindow) != "false"
    }

    private var rawExpandFoldersWhenShowingResults: Bool {
        storage.string(forKey: Keys.expandFoldersWhenShowingResults) == "true"
    }

    private var rawShowResultsEarly: Bool {
        storage.string(forKey: Keys.showResultsEarly) != "false"
    }

    private var rawIncludeSpotlightResults: Bool {
        storage.string(forKey: Keys.includeSpotlightResults) != "false"
    }

    private var rawQuitWhenAllWindowsAreClosed: Bool {
        storage.string(forKey: Keys.quitWhenAllWindowsAreClosed) != "false"
    }

    private func synchronizeGeneralPreferences() {
        try? storage.setCodable(
            GeneralSearchPreferences(
                launchShortcut: launchShortcut,
                activationMode: activationMode,
                openRecentSearchMenu: openRecentSearchMenu,
                restorePreviousSearch: restorePreviousSearch,
                tieResultsWindowToFindWindow: tieResultsWindowToFindWindow,
                quitWhenAllWindowsAreClosed: quitWhenAllWindowsAreClosed
            ),
            forKey: Keys.generalPreferences
        )
    }

    private func synchronizeSearchExecutionPreferences() {
        try? storage.setCodable(
            SearchExecutionPreferences(
                expandFoldersWhenShowingResults: expandFoldersWhenShowingResults,
                showResultsEarly: showResultsEarly,
                includeSpotlightResults: includeSpotlightResults
            ),
            forKey: Keys.searchExecutionPreferences
        )
    }

    private func synchronizeAppearancePreferences() {
        try? storage.setCodable(
            AppearancePreferences(
                preferredTheme: preferredTheme,
                preferredLanguage: preferredLanguage,
                resultsFontSize: resultsFontSize,
                dimColorHex: dimColorHex
            ),
            forKey: Keys.appearancePreferences
        )
    }

    private func synchronizeUpdatePreferences() {
        try? storage.setCodable(
            UpdatePreferences(
                updateCheckPolicy: updateCheckPolicy,
                autoDownloadUpdates: autoDownloadUpdates
            ),
            forKey: Keys.updatePreferences
        )
    }
}
